DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

for infile in *.nest; do 

  WHAT=`basename -s .nest ${infile}`
  EXPFILE=expected/${WHAT}.nest.out

  echo -e "Regenerateing ${WHAT}..."

  ${DIR}/nest-to-xml.tcl ${infile} > ${EXPFILE}

done
