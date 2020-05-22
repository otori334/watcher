#!/bin/bash 

IFS=$'\n' 

function print_time_row() { 
    { 
        echo -n "$1,"; 
        { time -p $2; } 2>&1 > /dev/null | 
            awk '{print $2}' | 
            tr \\n ,; 
        echo ''; 
    } | 
    tee -a ${3:-/dev/null} 
} 

if [ -d "test" ]; then 
    echo "${0##*/}: \"test\" directory already exists." 1>&2 
    exit 
    # rm test 
fi 

mkdir -p "test/state"{0..2} 

# sort の入力サイズである監視対象をふやす 
for ((n=1; n<=99; n++)); do 
    echo "${n}" > test/state1/${n} 
    echo "${n} ${n}" > test/state2/${n} 
    
    # model 
    for ((loop1=0; loop1<4; loop1++)); do 
        case ${loop1} in 
            0) 
                # intersection, merge, 
                function model() { 
                    if [ ${#current[*]} -eq 0 ]; then 
                        changed_filelist=() 
                    else 
                        changed_filelist=(` \
                            sort -m \
                                <(sort -mu \
                                    <(echo -n "${_last[*]}") \
                                    <(echo -n "${current[*]}")) \
                                <(echo -n "${_last[*]}") | 
                            uniq -u | 
                            cut -d' ' -f 3- | 
                            sort \
                        `) 
                    fi 
                } 
            ;; 
            1) 
                # intersection, no merge, 
                function model() { 
                    if [ ${#current[*]} -eq 0 ]; then 
                        changed_filelist=() 
                    else 
                        changed_filelist=(` \
                            sort \
                                <(sort -u \
                                    <(echo -n "${_last[*]}") \
                                    <(echo -n "${current[*]}")) \
                                <(echo -n "${_last[*]}") | 
                            uniq -u | 
                            cut -d' ' -f 3- | 
                            sort \
                        `) 
                    fi 
                } 
            ;; 
            2) 
                # sum, merge, 
                function model() { 
                    if [ ${#current[*]} -eq 0 ]; then 
                        changed_filelist=() 
                    else 
                        changed_filelist=(` \
                            sort -m \
                                <(sort -m \
                                    <(echo -n "${_last[*]}") \
                                    <(echo -n "${current[*]}") | 
                                    uniq -d) \
                                <(echo -n "${current[*]}") | 
                            uniq -u | 
                            cut -d' ' -f 3- | 
                            sort \
                        `) 
                    fi 
                } 
            ;; 
            3) 
                # sum, no merge, 
                function model() { 
                    if [ ${#current[*]} -eq 0 ]; then 
                        changed_filelist=() 
                    else 
                        changed_filelist=(` \
                            sort  \
                                <(sort  \
                                    <(echo -n "${_last[*]}") \
                                    <(echo -n "${current[*]}") | 
                                    uniq -d) \
                                <(echo -n "${current[*]}") | 
                            uniq -u | 
                            cut -d' ' -f 3- | 
                            sort \
                        `) 
                    fi 
                } 
            ;; 
        esac 
        
        # protocol 
        for ((loop2=0; loop2<2; loop2++)); do 
            if [ ${loop2} -eq 0 ]; then 
                # pre_sort 
                function protocol() { 
                    for ((_no=0; _no<=999; _no++)); do 
                        
                        # 一斉に生成 
                        local _last=(${current[@]}) 
                        current=(`shasum -a 256 test/state1/* . 2> /dev/null | sort `) 
                        model 
                        
                        # 一斉に更新 
                        local _last=(${current[@]}) 
                        current=(`shasum -a 256 test/state2/* . 2> /dev/null | sort `) 
                        model 
                        
                        # 一斉に消去 
                        local _last=(${current[@]}) 
                        current=(`shasum -a 256 test/state0/* . 2> /dev/null | sort `) 
                        model 
                    done 
                } 
            else 
                # no pre_sort 
                function protocol() { 
                    for ((_no=0; _no<=999; _no++)); do 
                            
                        # 一斉に生成 
                        local _last=(${current[@]}) 
                        current=(`shasum -a 256 test/state1/* . 2> /dev/null`) 
                        model 
                        
                        # 一斉に更新 
                        local _last=(${current[@]}) 
                        current=(`shasum -a 256 test/state2/* . 2> /dev/null`) 
                        model 
                        
                        # 一斉に消去 
                        local _last=(${current[@]}) 
                        current=(`shasum -a 256 test/state0/* . 2> /dev/null`) 
                        model 
                    done
                } 
                
            fi 
            
            # 事前に sort しない場合 morge が正しく働かないため除く 
            if [ \( ${loop1} -eq 0 -o ${loop1} -eq 2 \) -a ${loop2} -eq 1 ]; then 
                continue 
          	fi 
            
            if [ ! -f "test/${loop1}_${loop2}.csv" ]; then 
                echo "${loop1}_${loop2},,,," > "test/${loop1}_${loop2}.csv" 
                echo "n,real,user,sys," >> "test/${loop1}_${loop2}.csv" 
            fi 
            
            echo -n "${n}_${loop1}_${loop2}: "; date 
            
            print_time_row ${n} protocol "test/${loop1}_${loop2}.csv" 
            
            ((count++)) 
        done 
    done 
done 
paste -d "\0" test/*.csv > test/result.csv 
echo ${count} 
exit 