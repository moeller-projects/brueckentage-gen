# Brueckentage Generator

This PowerShell script calculates potential "bridge days" (Brueckentage) for a given year and state in Germany. Bridge days are workdays that can be taken off to create a longer holiday period by combining weekends and public holidays.

## Features

- Fetches public holidays for a specified year and German state using an API.
- Calculates free blocks of days, including weekends and holidays.
- Identifies optimal bridge days to maximize time off with minimal vacation days used.
- Outputs results grouped by month, prioritizing blocks with more free days.

## Requirements

- PowerShell
- Internet connection (to fetch holiday data from the API)

## Usage

Run the script with the following parameters:

- `Year`: The year for which you want to calculate bridge days (mandatory).
- `State`: The German state code (e.g., "BW", "BY") for which holidays should be considered (mandatory).
- `WeekendDays`: An array of integers representing weekend days (default is Sunday=0, Saturday=6).
- `VacationDays`: An array of strings representing additional vacation days in the format "yyyy-MM-dd".
- `Range`: The maximum number of consecutive days to consider for a block (default is 20).

### Example

```shell
.\brueckentage-gen.ps1 -Year 2025 -State BE
```

## Output

The script outputs potential bridge day blocks grouped by month, sorted by their effectiveness score. Only blocks with a score of 1.8 or higher are displayed, and up to five top-scoring blocks per month are shown.

## License

This project is licensed under the MIT License.

## Contributing

Contributions are welcome! Please fork the repository and submit a pull request with your changes.

## Contact

For questions or feedback, please open an issue on GitHub.
