DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

for infile in *.nest; do 

  WHAT=`basename -s .nest ${infile}`
  OUTFILE=${WHAT}.test.out
  EXPFILE=expected/${WHAT}.nest.out

  echo -e -n "Testing ${WHAT}..."

  ${DIR}/nest-to-xml.tcl ${infile} > ${OUTFILE}

  DIFF=`diff ${EXPFILE} ${OUTFILE}`

  if [ -z "$DIFF" ]; then
      echo "OK"
  else
      echo "FAILED"
  fi

  rm ${OUTFILE}

done
