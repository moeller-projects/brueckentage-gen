
<#PSScriptInfo

.VERSION 1.0

.GUID 61c8cca7-5460-47b4-b1f3-6ffb2b5afc1e

.AUTHOR Lukas Möller

.COMPANYNAME

.COPYRIGHT

.TAGS brueckentage

.LICENSEURI

.PROJECTURI

.ICONURI

.EXTERNALMODULEDEPENDENCIES

.REQUIREDSCRIPTS

.EXTERNALSCRIPTDEPENDENCIES

.RELEASENOTES

.PRIVATEDATA

#>

<#

.DESCRIPTION
This PowerShell script calculates potential "bridge days" (Brueckentage) for a given year and state in Germany. Bridge days are workdays that can be taken off to create a longer holiday period by combining weekends and public holidays.
#>
Param(
    [Parameter(Mandatory = $true)]
    [int]$Year,

    [Parameter(Mandatory = $true)]
    [ValidateSet("BW", "BY", "BE", "BB", "HB", "HH", "HE", "MV", "NI", "NW", "RP", "SL", "SN", "ST", "SH", "TH")]
    [string]$State,

    [int[]]$WeekendDays = @(0, 6), # Sunday=0, Saturday=6

    [string[]]$VacationDays = @(),

    [int]$Range = 20
)

function Get-Holidays {
    param (
        [int]$Year,
        [string]$State
    )
    $url = "https://feiertage-api.de/api/?jahr=$Year&nur_land=$State"
    try {
        return Invoke-RestMethod -Uri $url -Method Get
    } catch {
        Write-Error "ERROR: Error fetching holidays: $_"
        return @{}
    }
}

function ConvertTo-DayOfYearMap {
    param ($holidays)
    $map = @{}
    foreach ($holiday in $holidays.PSObject.Properties) {
        $date = Get-Date $holiday.Value.datum
        $map[$date.DayOfYear] = $holiday.Name
    }
    return $map
}

function Is-FreeDay {
    param ($dayIndex, $holidayMap, $vacationSet)
    $date = (Get-Date -Year $Year -Month 1 -Day 1).AddDays($dayIndex - 1)
    return ($WeekendDays -contains [int]$date.DayOfWeek) -or
            ($holidayMap.ContainsKey($dayIndex)) -or
            ($vacationSet.Contains($date.ToString("yyyy-MM-dd")))
}

function Get-FreeBlock {
    param ($startDay, $blockSize, $holidayMap, $vacationSet)
    $first = $startDay
    $last = $startDay + $blockSize - 1

    # Expand backward
    for ($i = 1; $i -lt 30; $i++) {
        if (-not (Is-FreeDay -dayIndex ($first - $i) -holidayMap $holidayMap -vacationSet $vacationSet)) {
            $first = $first - $i + 1
            break
        }
    }

    # Expand forward
    for ($i = 1; $i -lt 30; $i++) {
        if (-not (Is-FreeDay -dayIndex ($last + $i) -holidayMap $holidayMap -vacationSet $vacationSet)) {
            $last = $last + $i - 1
            break
        }
    }

    # Count free days
    $daysAlreadyFree = 0
    for ($i = $first; $i -le $last; $i++) {
        if (Is-FreeDay -dayIndex $i -holidayMap $holidayMap -vacationSet $vacationSet) {
            $daysAlreadyFree++
        }
    }

    $freeDays = $last - $first + 1
    $bridgeDays = $freeDays - $daysAlreadyFree

    return @{
        First = $first
        Last = $last
        BridgeDays = $bridgeDays
        TotalDays = $freeDays
    }
}

$holidays = Get-Holidays -Year $Year -State $State
$holidayMap = ConvertTo-DayOfYearMap -holidays $holidays
$vacationSet = [System.Collections.Generic.HashSet[string]]::new()
$VacationDays | ForEach-Object { [void]$vacationSet.Add($_) }

$results = @()
$uniqueBlocks = [System.Collections.Generic.HashSet[string]]::new()
$daysInYear = [DateTime]::IsLeapYear($Year) ? 366 : 365

for ($d = 1; $d -le $daysInYear; $d++) {
    for ($r = 1; $r -le $Range; $r++) {
        if ($d + $r - 1 -gt $daysInYear) {
            continue
        }

        if (Is-FreeDay -dayIndex $d -holidayMap $holidayMap -vacationSet $vacationSet) {
            continue
        }

        $block = Get-FreeBlock -startDay $d -blockSize $r -holidayMap $holidayMap -vacationSet $vacationSet
        if ($block.BridgeDays -le 0) {
            continue
        }

        $startDate = (Get-Date -Year $Year -Month 1 -Day 1).AddDays($block.First - 1).ToString("yyyy-MM-dd")
        $endDate = (Get-Date -Year $Year -Month 1 -Day 1).AddDays($block.Last - 1).ToString("yyyy-MM-dd")
        $blockIdentifier = "$startDate-$endDate"

        if ($uniqueBlocks.Add($blockIdentifier)) {
            $score = if ($block.BridgeDays -gt 0) {
                $block.TotalDays / $block.BridgeDays
            } else {
                -1
            }

            # Prioritize blocks starting or ending with a free day and having more free days than half the range
            $startsWithFreeDay = Is-FreeDay -dayIndex $block.First -holidayMap $holidayMap -vacationSet $vacationSet
            $endsWithFreeDay = Is-FreeDay -dayIndex $block.Last -holidayMap $holidayMap -vacationSet $vacationSet
            $moreThanHalfFree = $block.TotalDays / 2 -lt $daysAlreadyFree

            if (($startsWithFreeDay -or $endsWithFreeDay) -and $moreThanHalfFree) {
                $score += 1 # Boost score for priority
            }

            $results += [PSCustomObject]@{
                Start = $startDate
                End = $endDate
                BridgeDays = $block.BridgeDays
                TotalFreeDays = $block.TotalDays
                Score = [math]::Round($score, 2)
            }
        }
    }
}

$results |
        Group-Object { (Get-Date $_.Start).Month } |
        ForEach-Object {
            $monthName = (Get-Culture).DateTimeFormat.GetMonthName($_.Name)
            Write-Output "# $($monthName):"
            $_.Group | Where-Object { $_.Score -ge 1.8 } | Sort-Object -Property Score -Descending | Select-Object -First 5 | Format-Table -AutoSize
        }
