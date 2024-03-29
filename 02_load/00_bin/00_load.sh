#! /bin/bash
#+----------------------------------------------------------------------------+
#|1, Use to load data from file to oracle database.                           |
#|2, Config file in ../01_cfg/load.cfg.                                       |
#|3, Data file should put in ../02_dat/.                                      |
#|4, Log files are in ../03_log/.                                             |
#|5, Control files are in ../04_ctl/                                          |
#|6, Not support multiprocess n parallel yet, its the begining of Zima Blue.  |
#|7, Changelog at the end of Program.                                         |
#|8, Build by Chewie, Oct,10,2019.                                            |
#+----------------------------------------------------------------------------+

echo "[`date '+%Y-%m-%d %H:%M:%S'`]at the very begining<<<<<<<<<<<<<<<<<<<<<<<\
<<<<<<<<<<<<<<"

declare -r binpath="../00_bin/"
declare -r cfgpath="../01_cfg/"
declare -r datpath="../02_dat/"
declare -r logpath="../03_log/"
declare -r ctlpath="../04_ctl/"
declare -r cfgFile=${cfgpath}"load.cfg"
declare -r calFile="${logpath}calculate_table.unl" 
declare -r cal_tmp="${logpath}cal.tmp"


dsn=`grep -A 1 "\[dsn\]" ${cfgFile} | grep -v "\[dsn\]"`
inputspearatore=`grep -A 1 "\[separator\]" ${cfgFile} | grep -v "\[separator\]"`
if [[ ${inputspearatore} == "default" ]];then
    declare -r separatore=" "
else
    declare -r separatore=${inputspearatore}
fi
tabListBegin=`grep -n -A 1 "\[tableList\]" ${cfgFile} | \
grep -v "\[tableList\]" | awk -F"-" '{print $1}'`
tabListEnd=`grep -n -B 1 "\[tableListEnd\]" ${cfgFile} | \
grep -v "\[tableListEnd\]" | awk -F"-" '{print $1}'`


echo -e "+----------------------------------------+"
echo -e " dsn is: ${dsn}\n separatore is: ${separatore}"
echo -e "+----------------------------------------+"

#calcluate table data before loading
echo -e "\n\
+----------------------------------------+
|calculate table before loading...       |
+----------------------------------------+"

`cat /dev/null > ${calFile}`
for calnum in `sed -n "${tabListBegin},${tabListEnd}p" ${cfgFile}`
do
    bef_tab_name=`echo ${calnum} | awk -F"|" '{print $1}'`

    `cat /dev/null > ${cal_tmp}` 
    sqlplus -S ${dsn} <<INPUT > ${cal_tmp}
    select count(*) from ${bef_tab_name};
INPUT
    cal_num=`cat ${cal_tmp} | grep -v "COUNT(" | grep -v "-" |\
             grep -v "^ *$" | awk '{print $1}'`
    echo " ${bef_tab_name} before is: ${cal_num}"
    echo "${bef_tab_name}|${cal_num}|" >> ${calFile}
done

#----------------------------start multi processes------------------------------#
trap "exec 1000>&-;exec 1000<&-;exit 0" 2
Pfifo="/tmp/$$.fifo"
mkfifo ${Pfifo}
exec 1000<>${Pfifo}
rm -f ${Pfifo}

for((i=0; i<${process}; i++))
do
    echo
done >&1000


#loading
declare count=0
echo -e "\n\
+------------------Don't panic. Keep calm and carry on.----------------------+"

for cursor in `sed -n "${tabListBegin},${tabListEnd}p" ${cfgFile}`
do
    read -u1000
    table_name[${count}]=`echo ${cursor} | awk -F"|" '{print $1}'`
    file_nmae[${count}]=`echo ${cursor} | awk -F"|" '{print $2}'`
    struct[${count}]="${ctlpath}${table_name}_struct.tmp"
    ctl_file[${count}]="${ctlpath}${table_name}.ctl"
    log_file[${count}]="${logpath}${table_name}.log"
    lod_file[${count}]="${logpath}${table_name}.lod"
    
    sqlplus -S ${dsn} <<INPUT > ${struct}
    desc ${table_name[${count}]};
INPUT
    
    fields[${count}]=`cat ${struct[${count}]} | grep -v "Name" | grep -v "-" | grep -v "^ *$" | \
            awk '{if ($2=="DATE") print $1," \"to_date(:"$1\
            ", '\''yyyy-mm-dd hh24:mi:ss'\'')\","; else print $1","}'`
    
    echo "\
    load data
    infile '${datpath}${file_nmae[${count}]}'
    append into table ${table_name[${count}]}
    fields terminated by '${separatore}'
    (
    ${fields[${count}]})" > ${ctl_file[${count}]}
    
    `sed -i 's/,)/)/g' ${ctl_file[${count}]}`

    {
        echo "[`date '+%Y-%m-%d %H:%M:%S'`]${table_name[${count}]} start<<<<"
        sqlldr ${dsn} control=${ctl_file[${count}]} log=${log_file[${count}]} > ${lod_file[${count}]}
        err_num[${count}]=`grep "ORA-" ${log_file[${count}]} | wc -l` 
        if [[ ${err_num[${count}]}==0 ]]; then
            echo "[`date '+%Y-%m-%d %H:%M:%S'`]${table_name[${count}]} finished>>>>"
        else
            echo "[`date '+%Y-%m-%d %H:%M:%S'`]${table_name[${count}]} meet errors /0.0\\"
        fi

        sleep 1

        echo >&1000
    }&

    ((count++))

done

wait
exec 1000>&-

echo -e "\n\
+------------------So long, and thanks for all the fish----------------------+"

#checking
echo -e "\n\
+-------------------------------+
|checking loading result...     |
+-------------------------------+"

for i in `cat ${calFile}`
do
    aftCal_tab=`echo ${i} | awk -F"|" '{print $1}'`
    aftCal_bef=`echo ${i} | awk -F"|" '{print $2}'`
    sqlplus -S ${dsn} <<INPUT > ${cal_tmp}
    select count(*) from ${aftCal_tab};
INPUT
    aftCal_aft=`cat ${cal_tmp} | grep -v "COUNT(" | grep -v "-" |\
                grep -v "^ *$" | awk '{print $1}'`
    aftCal_load=$((aftCal_aft - aftCal_bef))
    aftCal_file=`grep "${aftCal_tab}|" ${cfgFile} | awk -F"|" '{print $2}'`
    aftCal_filenum=`wc -l ${datpath}${aftCal_file} | awk '{print $1}'`
    aftCal_dif=$((aftCal_filenum - aftCal_load))
    echo -e "${aftCal_tab}->before:${aftCal_bef}, after:${aftCal_aft}, \
load:${aftCal_load}, file num:${aftCal_filenum}, difference:${aftCal_dif}\n"
done

#remove all temp files
`rm -f ${logpath}*.tmp`
`rm -f ${ctlpath}*.tmp`

echo "[`date '+%Y-%m-%d %H:%M:%S'`]Its all finished>>>>>>>>>>>>>>>>>>>>>>>>>>>>\
>>>>>>>>>>>>>>"
