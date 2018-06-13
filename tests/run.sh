#!/bin/bash

export DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH:`ocamlfind query Z3`
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:`ocamlfind query Z3`

#cd $CERB_PATH/tests

source tests.sh

mkdir -p tmp

pass=0
fail=0

JOUTPUT=""
JOUTPUT_FILE="ci_results.xml"

# Arguments:
# 1: test case name
# 2: result (0 is success)
function report {
  #If the test should fail
  if [[ $1 == *.fail.c ]]; then
    res="1 - $2";
  else
    res=$2;
  fi

  #If the test is about undef
  if [[ $1 == *.undef.c ]]; then
    cat tmp/result | grep Undefined
    res=$?
  fi

  if [[ "$((res))" -eq "0" ]]; then
    res="\033[1m\033[32mPASSED!\033[0m"
    pass=$((pass+1))
    JOUTPUT+="\t<testcase name=\"$1\"/>\n"
  else
    res="\033[1m\033[31mFAILED!\033[0m"
    fail=$((fail+1))
    cat tmp/result tmp/stderr
    JOUTPUT+="\t<testcase name=\"$1\">\n"
    JOUTPUT+="\t\t<error message=\"fail\">`cat tmp/result tmp/stderr`</error>\n"
    JOUTPUT+="\t</testcase>\n"
  fi

  echo -e "Test $1: $res"
}

# Arguments:
# 1: file name
# 2: relative path
function test_exec {
  ../cerberus --exec --batch $2/$1 > tmp/result 2> tmp/stderr
  if [ -f $2/expected/$1.expected ]; then
    cmp --silent tmp/result $2/expected/$1.expected
  fi
  report $1 $?
}

# Arguments:
# 1: file name
# 2: relative path
function test {
  ../cerberus $2/$1 > tmp/result 2> tmp/stderr
  report $1 $?
}

# Running parsing tests
for file in suite/parsing/*.c
do
  test $file .
done

# Running ci tests
for file in "${citests[@]}"
do
  test_exec $file ci
done

# Running gcc torture
for file in gcc-torture/breakdown/success/*.c
do
  ../cerberus $file --exec --batch > tmp/result 2> tmp/stderr
  grep -E "Specified.0.|EXIT" tmp/result > /dev/null
  report $file $?
done

echo "PASSED: $pass"
echo "FAILED: $fail"

# JUnit XML output (for Jenkins report)
echo "<testsuites>" > $JOUTPUT_FILE
echo "<testsuite name=\"ci\" tests=\"$((pass + fail))\" failures=\"${fail}\" timestamp=\"$(date)\">" >> $JOUTPUT_FILE
echo -e ${JOUTPUT} >> $JOUTPUT_FILE
echo "</testsuite>" >> $JOUTPUT_FILE
echo "</testsuites>" >> $JOUTPUT_FILE

