#!/bin/bash
# 外部ファイルを使って cron で使えるようにした

# see also
# http://mizti.hatenablog.com/entry/2013/01/27/204343
# https://qiita.com/tamanobi/items/74b62e25506af394eae5
# https://www.softel.co.jp/blogs/tech/archives/1332
# https://qiita.com/stc1988/items/464410382f8425681c20

IFS=$'\n' # 空白を含む名前を扱う

readonly LOG="./watcher2.log"

# 監視にかなうディレクトリを配列 target_dir に記録する
# 重複を除き，包含関係がある場合は下位のディレクトリを除く
function setup_target_dir () {
    
    # 実在するディレクトリを抽出する
    local _exist_dir=()
    local _exist_index=0
    while [ "$1" != "" ]; do
        if [ -d "$1" ]; then
            _exist_dir[$((_exist_index++))]=`cd "$1"; pwd`
        elif [ -f "$1" ]; then
            echo "${CMD_NAME}: $1: Please specify directory." 1>&2
        else
            echo "${CMD_NAME}: $1: No such directory." 1>&2
        fi
        shift
    done
    
    # 実在するディレクトリが指定されない場合は終了する
    if [ ${_exist_index} -eq 0 ]; then
        echo "${CMD_NAME}: Please specify directory." 1>&2
        exit 1
    fi
    
    # 重複関係がある場合，重複を除く
    local _sort_dir=(`sort -u <<< "${_exist_dir[*]}"`)
    
    # 包含関係がある場合，下位ディレクトリを除く
    local _track_dir=(${_sort_dir[@]})
    local _unset_dir=(${_sort_dir[@]})
    local _lead_index=0
    local _trail_index=0
    local _lead_dir
    local _trail_dir
    until [ ${_lead_index} -gt ${#_track_dir[@]} ]; do
        ((_lead_index++))
        _lead_dir="${_track_dir[${_lead_index}]}"
        _trail_dir="${_track_dir[${_trail_index}]}"
        if [ "${_lead_dir}" != "${_lead_dir#${_trail_dir}/}" ]; then
            unset _unset_dir[${_lead_index}]
        else
            _trail_index=${_lead_index}
        fi
    done
    target_dir=(${_unset_dir[@]})
    
    #echo "${CMD_NAME}: setup_target_dir: check${IFS}${target_dir[*]}" 1>&2
    return 0
}
#setup_target_dir $@; exit


# 指定された秒数前の時刻を touch -t が扱えるフォーマットで出力する
# BSD date と GNU Core Utilities date はオプション体系が異なる
# Thanks to https://uec.usp-lab.com/CMD_TIPS/CGI/CMD_TIPS.CGI?POMPA=TIPS_date_gnu
if date -v-1d &> /dev/null; then
    function date_tt () {
        eval date '-v-'"$1"'S' '"+%Y%m%d%H%M.%S"'
        return 0
    }
elif date -d "1 day ago" &> /dev/null; then
    function date_tt () {
        date -d "$1 seconds ago" "+%Y%m%d%H%M.%S"
        return 0
    }
else
    echo "${CMD_NAME}: You can't execute this command." 1>&2
    exit 1
fi


# 名称変更・追加・更新されたファイルを抽出し，配列 rename_create_modify に記録する
# rename_create_modify 関数が初めて呼ばれた場合，ファイル抽出は行わない
function rename_create_modify () {
    
    # UNIX時間
    local _nowtime=`date "+%s"`
    local _oldtime=`date -r "${LOG}" "+%s" 2> /dev/null || touch "${LOG}"`
    touch -t `date_tt $((${_nowtime}-${_oldtime:-${_nowtime}}+1))` "${LOG}"
    
    local _last=(`cat "${LOG}"`)
    
    # GNU 版 xargs は下の方法では動かないので find {} などを find $@ に置き換える．もっといい方法があるかもしれないが調べてない．
    local _file_list=`echo $@ |
        xargs -n 1 -P 2 -I{} \
            find {} \( \
                -name 'node_modules' -o \
                -name '.git' -o \
                -name '.DS_Store' \) \
                    -prune -o \
                    -type f \
                    -newer "${LOG}" \
                    -print`
    
    # ここの前後をパイプで繋げると GNU 版 find の -newer が "${LOG}" へのリダイレクトを検知してしまうので，それを防ぐために変数を介している． BSD 版 find ならパイプを使っても問題ない．
    
    shasum -a 256 ${_file_list} . 2> /dev/null | sort > "${LOG}"
    
    # 粗く割り出したファイルのハッシュ値をバッファと比較し，ファイルを抽出する
    if [ `wc -l "${LOG}"` == "0" -o ! "${_oldtime}" ]; then
        
        rename_create_modify=()
    else
        # 内容が変更されたファイル・名称が変更された直後のファイル・追加されたファイルを抽出する
            # 片方の配列にあってもう片方にはないデータを見つける
                # Thanks to https://anmino.hatenadiary.org/entry/20091020/1255988532
            # sort 高速化
                # Thanks to https://genzouw.com/entry/2019/04/22/175208/1393
                # 変化するファイル数が100程度の場合，外部コマンド起動時間の影響が高速化の影響を上回り，数ミリ秒遅い
                # 変化するファイル数が膨大な場合に効果を発揮する
        rename_create_modify=(` \
            sort -m \
                <(sort -mu <(echo -n "${_last[*]}") "${LOG}") \
                <(echo -n "${_last[*]}") |
            uniq -u |
            cut -d' ' -f 3-
        `)
    fi
    
    #echo "${rename_create_modify[*]}" 1>&2
    return 0
}

setup_target_dir $@
rename_create_modify ${target_dir[@]}
echo -n "${rename_create_modify[*]}" #1>&2
#cat "${LOG}"
