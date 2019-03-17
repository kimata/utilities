#!/usr/bin/env zsh

if [ $# -ne 1 ]; then
    echo "usage: $0 PATH"
    exit
fi

TS_DIR=${1:a}

if [ ! -e $TS_DIR ]; then
    echo "ERROR: $TS_DIR does not exist."
    exit
fi

MP4_DIR=$TS_DIR
WORK_DIR="$TS_DIR/encode/work"
DONE_DIR="$TS_DIR/encode/done"
LOG_DIR="$TS_DIR/encode/log"

echo "SART ENCODING: $WORK_DIR"
echo ""

mkdir -p $WORK_DIR
mkdir -p $DONE_DIR
mkdir -p $LOG_DIR

i=0
for ts_file in $TS_DIR/*.ts; do
    i=$((i + 1))
    mp4_file=$WORK_DIR/${ts_file:r:t}.mp4
    log_file=$LOG_DIR/${ts_file:r:t}.log

    echo "Process[$i]: ${ts_file:r:t}"
    time_start=$(date +%s)

    dur=$(ffmpeg -i $ts_file 2>&1 | sed -n "s/.* Duration: \([^,]*\), start: .*/\1/p")
    fps=$(ffmpeg -i $ts_file 2>&1 | sed -n "s/.*, \(.*\) tbr.*/\1/p")
    h=$(echo $dur | cut -d":" -f1)
    m=$(echo $dur | cut -d":" -f2)
    s=$(echo $dur | cut -d":" -f3)
    frame_num_ts=${$(((h*3600+m*60+s)*fps))%%.*}

    ffmpeg -i $ts_file -vcodec libx265 -preset slow -crf 24 -pix_fmt yuv420p -vf bwdif=1 -codec:a copy -bsf:a aac_adtstoasc -y $mp4_file |& awk '1;{fflush()}' RS='\r' >$log_file &

    ffmpeg_pid=$!
    while ps -p $ffmpeg_pid>/dev/null  ; do
    	frame_done=$(tail -n 1 $log_file | awk 'match($0, /frame=\s*([0-9]+)/, m) { print m[1] }' )
  	if [[ -n "$frame_done" ]]; then
  	    progress=$(printf "%.1f" $((frame_done*100.0/frame_num_ts/2)))
  	    echo -n "\r\t$progress %"
  	    sleep 1
  	fi
    done
    sleep 1
    time_end=$(date +%s)
    
    dur=$(ffmpeg -i $ts_file 2>&1 | sed -n "s/.* Duration: \([^,]*\), start: .*/\1/p")
    fps=$(ffmpeg -i $ts_file 2>&1 | sed -n "s/.*, \(.*\) tbr.*/\1/p")
    h=$(echo $dur | cut -d":" -f1)
    m=$(echo $dur | cut -d":" -f2)
    s=$(echo $dur | cut -d":" -f3)
    frame_num_mp4=${$(((h*3600+m*60+s)*fps))%%.*}

    if [[ $(((frame_num * 2) - frame_num_mp4)) -gt 2 ]]; then
        echo "ERROR: The number of frames did not match. exp:$((frame_num * 2)) <-> act:$frame_num_mp4"
	exit
    fi

    echo ""
    echo -n "\tElapsed Time: "
    date -d@$(($time_end-$time_start)) -u +%H:%M:%S
    echo ""

    touch -c -r $ts_file $mp4_file
    
    mv -f $ts_file $DONE_DIR
    mv -f $mp4_file $MP4_DIR
done
