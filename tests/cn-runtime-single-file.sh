#! /bin/bash

INPUT_FN=$1
INPUT_BASENAME=$(basename $INPUT_FN .c)
INPUT_DIRNAME=$(dirname $INPUT_FN)
INPUT_EXEC_DIR=$INPUT_DIRNAME/exec/$INPUT_BASENAME-exec
INPUT_EXEC_FILE=$INPUT_EXEC_DIR/$INPUT_BASENAME-exec.c

mkdir $INPUT_DIRNAME/exec
rm -rf $INPUT_EXEC_DIR
echo "Creating $INPUT_EXEC_DIR directory..."
mkdir $INPUT_EXEC_DIR


echo "Generating C files from CN-annotated source..."
if ! cn $INPUT_FN --output_decorated=$INPUT_BASENAME-exec.c --output_decorated_dir=$INPUT_EXEC_DIR/
then
    echo Generation failed.
else 
    echo Done!
    cd $INPUT_EXEC_DIR
    echo Compiling...
    if ! cc -I$OPAM_SWITCH_PREFIX/lib/cn/runtime/include  $OPAM_SWITCH_PREFIX/lib/cn/runtime/libcn.a $INPUT_BASENAME-exec.c cn.c
    then
        echo Compilation failed.
    else 
        echo Done!
        echo Linking...
        if ! cc -o $INPUT_BASENAME-exec-output -g $INPUT_BASENAME-exec.o cn.o alloc.o hash_table.o cn_utils.o
        then 
            echo Linking failed.
        else 
            echo Done!
            echo Running binary...
            if ./${INPUT_BASENAME}-exec-output
            then 
                echo "Success!"
            else
                echo "Test failed."
            fi
        fi
    fi
fi
