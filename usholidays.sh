#!/bin/bash

myyear="$1"
dformat='+%A, %B %d, %Y'
spacing=30
holidays_txt="${HOME}/.bond/holidays.txt"

if [[ -z "${myyear}" ]]
then
  myyear=$( date +%Y )
fi

function nth_xday_of_month {

  my_nth=$1
  my_xday=$2
  my_month=$( printf "%02d" "$3" )
  my_year=$4

  case "$my_nth" in

  1)  mydate=$(echo {01..07})
      ;;
  2)  mydate=$(echo {08..14})
      ;;
  3)  mydate=$(seq 15 21)
      ;;
  4)  mydate=$(seq 22 28)
    ;;
  5)  mydate=$(seq 29 31)
      ;;
  *) echo "Echo wrong day of the week"
    exit 1
    ;;
  esac


  for x in $mydate
  do
    nthday=$(date '+%u' -d "${my_year}${my_month}${x}")
    if [ "$nthday" -eq "$my_xday" ]
    then
      echo "${my_year}-${my_month}-${x}"
      break
    fi
  done
}

# Function to check if given date is Saturday or Sunday and adjust accordingly
output_holiday() {
  holiday_name="${1}"
  date_input="${2}"  # Get the date passed as argument
  moveforward="${3}"
  observed=""

  day=$(date -d "$date_input" +%u)  # Get the day of the week for the given date
  dateoutput=$(date "${dformat}" -d "${date_input}" )

  printf "%-${spacing}s%s\n" "${holiday_name}:" "${dateoutput}" >> "${holidays_txt}"
  if [[ "${day}" -eq 6 ]]
  then  # If it's Saturday
    if [[ -z "${moveforward}" ]]
    then
      observed=$( date "${dformat}" -d "$date_input - 1 day" )
    else
      observed=$( date "${dformat}" -d "$date_input + 2 days" )
    fi
  elif [[ "${day}" -eq 7 ]]
  then  # If it's Sunday
    observed=$( date "${dformat}" -d "$date_input + 1 day" )
  fi
  if [[ -n "${observed}" ]]
  then
    printf "%-${spacing}s%s\n" "${holiday_name} observed:" "${observed}" >> "${holidays_txt}"
  fi
}

#Memorial Day; last Monday in May.
for day in {31..1}
do
    day_of_week=$(date -d "${myyear}-05-${day}" +%u)
    if [[ "$day_of_week" -eq 1 ]]
    then
      memday="${day}"
      break
    fi
done

# Clean the holidays.txt file if exists
> "${holidays_txt}"

output_holiday "New Year's Day" "${myyear}-01-01" "1"
output_holiday "Martin Luther King, Jr. Day" "$(nth_xday_of_month 3 1 1 ${myyear})" #3rd Monday of Jan
output_holiday "Presidents' Day" "$(nth_xday_of_month 3 1 2 ${myyear})" #3rd Monday of Feb
output_holiday "Memorial Day" "${myyear}-05-${memday}"
output_holiday "Juneteenth" "${myyear}-06-19"
output_holiday "Independence Day" "${myyear}-07-04"
output_holiday "Labor Day" "$(nth_xday_of_month 1 1 9 ${myyear})" #1st Monday of Sept
output_holiday "Columbus Day" "$(nth_xday_of_month 2 1 10 ${myyear})" #2nd Monday of Oct
output_holiday "Veteran's Day" "${myyear}-11-11"
output_holiday "Thanksgiving" "$(nth_xday_of_month 4 4 11 ${myyear})" #4th Thursday of Nov
output_holiday "Black Friday" "$(nth_xday_of_month 4 5 11 ${myyear})" #4th Friday of Nov
output_holiday "Christmas Eve" "${myyear}-12-24" "1"
output_holiday "Christmas Day" "${myyear}-12-25"

cat "${holidays_txt}"
