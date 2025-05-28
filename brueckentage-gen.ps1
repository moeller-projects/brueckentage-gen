param (
    [Parameter(Mandatory = $true)]
    [int]$Year,

    [Parameter(Mandatory = $true)]
    [ValidateSet("BW", "BY", "BE", "BB", "HB", "HH", "HE", "MV", "NI", "NW", "RP", "SL", "SN", "ST", "SH", "TH")]
    [string]$State,

    [int[]]$WeekendDays = @(0, 6), # Sunday=0, Saturday=6

    [string[]]$VacationDays = @(),

    [int]$Range = 20
)

function Get-Holidays
{
    param (
        [int]$Year,
        [string]$State
    )
    $url = "https://feiertage-api.de/api/?jahr=$Year&nur_land=$State"
    try
    {
        return Invoke-RestMethod -Uri $url -Method Get
    }
    catch
    {
        Write-Error "ERROR: Error fetching holidays: $_"
        return @{ }
    }
}

function ConvertTo-DayOfYearMap
{
    param ($holidays)
    $map = @{ }
    foreach ($holiday in $holidays.PSObject.Properties)
    {
        $date = Get-Date $holiday.Value.datum
        $map[$date.DayOfYear] = $holiday.Name
    }
    return $map
}

function Is-FreeDay
{
    param ($dayIndex, $holidayMap, $vacationSet)
    $date = (Get-Date -Year $Year -Month 1 -Day 1).AddDays($dayIndex - 1)
    $isWeekend = $WeekendDays -contains [int]$date.DayOfWeek
    $isHoliday = $holidayMap.ContainsKey($dayIndex)
    $isVocation = $vacationSet.Contains($date.ToString("yyyy-MM-dd"))
    $isFreeDay = ($isWeekend -or $isHoliday -or $isVocation)
    return $isFreeDay
}

function Get-FreeBlock
{
    param ($startDay, $blockSize, $holidayMap, $vacationSet)
    $first = $startDay
    $last = $startDay + $blockSize - 1

    # Expand backward
    for ($i = 1; $i -lt 30; $i++) {
        if (-not (Is-FreeDay -dayIndex ($first - $i) -holidayMap $holidayMap -vacationSet $vacationSet))
        {
            $first = $first - $i + 1
            break
        }
    }

    # Expand forward
    for ($i = 1; $i -lt 30; $i++) {
        if (-not (Is-FreeDay -dayIndex ($last + $i) -holidayMap $holidayMap -vacationSet $vacationSet))
        {
            $last = $last + $i - 1
            break
        }
    }

    # Count free days
    $daysAlreadyFree = 0
    for ($i = $first; $i -le $last; $i++) {
        if (Is-FreeDay -dayIndex $i -holidayMap $holidayMap -vacationSet $vacationSet)
        {
            $daysAlreadyFree++
        }
    }

    $freeDays = $last - $first + 1;
    $bridgeDays = $freeDays - $daysAlreadyFree

    return @{
        First = $first
        Last = $last
        BridgeDays = $bridgeDays
        TotalDays = $last - $first + 1
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
        if ($d + $r - 1 -gt $daysInYear)
        {
            continue
        }

        if (Is-FreeDay -dayIndex $d -holidayMap $holidayMap -vacationSet $vacationSet)
        {
            continue
        }

        $block = Get-FreeBlock -startDay $d -blockSize $r -holidayMap $holidayMap -vacationSet $vacationSet
        if ($block.BridgeDays -le 0)
        {
            continue
        }

        $startDate = (Get-Date -Year $Year -Month 1 -Day 1).AddDays($block.First - 1).ToString("yyyy-MM-dd")
        $endDate = (Get-Date -Year $Year -Month 1 -Day 1).AddDays($block.Last - 1).ToString("yyyy-MM-dd")
        $blockIdentifier = "$startDate-$endDate"

        if ( $uniqueBlocks.Add($blockIdentifier))
        {
            if ($block.BridgeDays -gt 0)
            {
                $score = $block.TotalDays / $block.BridgeDays
            }
            else
            {
                $score = -1
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

$results | Where-Object { $_.Score -ge 1.8 } | Sort-Object -Property Score -Descending | Format-Table -AutoSize
