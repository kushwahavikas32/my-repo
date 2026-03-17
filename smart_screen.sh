#!/bin/bash
DATE=`date +%d%m%y`
DATE1=`date +%d:%m:%y`
TIME=`date +"%T"`
var=0
OUTPUT=/tmp/output_results.txt
>$OUTPUT
MESSAGE=/tmp/top_sender_in10min_"$DATE".txt
>$MESSAGE
SEND_MAIL=/tmp/output_results_sendmail.txt
for ((i=1; i<=29; i++))
do
sleep 2
count1=`/opt/zimbra/libexec/zmqstat | grep "active" | cut -f 2 -d=`
#echo $count1
    if [ "$count1" -ge 6 ]
                           then i=30
      else
	      echo "$i Mail system hove low queue in Active spool="$count1""
    fi
done


if [ "$count1" -ge 6 ]
then
systemctl start iptables
tail -n 800000 /var/log/zimbra.log |awk "/^$(date --date="-5 min" "+%b %_d %H:%M")/{p++} p" | grep "from=<" |grep  active | cut -d "<" -f2 | cut -d ">" -f1 |sort| uniq -c|sort -n | cut -d '_' -f2 | tail -10 >$MESSAGE
sed -i "s/[[:space:]]\+/ /g" $MESSAGE
sed -i "s/^ //g" $MESSAGE
sed -i "s/ /;/g" $MESSAGE
#Email Excluder Programm
>/tmp/includer
  while IFS=";" read Emailid Count
    do

            Ccount=$(cat $MESSAGE| grep -w $Emailid |cut -d ";" -f1)

       if [ ! -z "$Ccount" ];then

                  if [ $Ccount -le $Count ]
                        then
                        sed -i "/$Emailid/d" $MESSAGE
                        echo "$Emailid" >>/tmp/includer
                  fi

        fi
     done </top_sender_in10min_exclude_list.txt
#END Email Excluder Programm


############# External Mail Includer
if [ -s /tmp/includer ] ;then
echo test1
LocalDomains=`sed -e "s/ /|/g" /domain.txt`
while read excluderID
do
        echo -n "Checking external Mails of Account $excluderID"
        QueueIDs=$(tail -n 8000000 /var/log/zimbra.log|awk "/^$(date --date="-10 min" "+%b %_d %H:%M")/{p++} p" |grep -i "queue active"| grep -i "$excluderID" | cut -d ":" -f4|cut -d " " -f2)
  Countoutermail=$(tail -n 8000000 /var/log/zimbra.log|awk "/^$(date --date="-10 min" "+%b %_d %H:%M")/{p++} p"|grep -i "postfix" | grep -E "`echo $QueueIDs|sed "s/ /|/g"`" | grep -i "OK"|grep -i sent | grep -v "MTA"|grep -Ev "$LocalDomains" | wc -l)

        echo "..... $Countoutermail"
if [ $Countoutermail -ge "10" ]  ## INTERNAL_DOAMIN and External domain mail control

then echo "$Countoutermail;$excluderID" >>$MESSAGE
	 sed -i "/pbhw.support@sahara.in/d" $MESSAGE #External bulk Mail Sent Request
	 sed -i "/noreply.hqlife@sahara.in/d" $MESSAGE ##External bulk Mail Sent Request

        echo "Limite Reached!!!External Mails send by ID $excluderID with no. $Countoutermail"
fi

done</tmp/includer
fi
##############




while IFS=";" read count id
 do
   if [ "$count" -ge "15" ]   # message Limite
      then
	      if [[ ! -z $id ]]
	      then
        echo "Holding all message from $id"
       # /opt/zimbra/bin/zmprov ma $id zimbraAccountStatus closed
        /opt/zimbra/common/sbin/postqueue -p | grep -w "$id" | grep `date +%b`|cut -d " " -f1 |tr -d '!*' | /opt/zimbra/common/sbin/postsuper -h - >> $OUTPUT
     #   su - zimbra -c "/opt/zimbra/bin/zmprov ma $id zimbraAccountStatus closed"
############################ for External Email ID that is not closeable in zimbra side. so here we can add into spam DB /opt/zimbra/data/spamassassin/localrules/external.cf
#domain update time
		DUtime=`date "+%k%M"` # update db every day @ 11:30 AM
				if [ "$DUtime" -eq "1130" ]  || [  ! -f "/domain.txt" ]
					then
					/opt/zimbra/bin/zmprov -l gad >/tmp/domain.txt
					single_line=`cat /tmp/domain.txt`
					echo $single_line >/domain.txt
				fi
#if external domain then add into blacklist file
check_domain=`echo $id |tr '[:upper:]' '[:lower:]'| cut -d "@" -f2`
echo  "domain name $check_domain"

INTERNAL_DOAMIN=$(cat /domain.txt| /usr/bin/grep -w $check_domain)
                                if [[ ! -z "$INTERNAL_DOAMIN" ]]
                   		then
				        #opt/zimbra/bin/zmprov ma $id zimbraAccountStatus closed
					su - zimbra -c "/opt/zimbra/bin/zmprov ma $id zimbraAccountStatus closed"
					echo "local doman IDs will closed"
				else
                                        
					precount=$(cat /opt/zimbra/data/spamassassin/localrules/external.cf | wc -l )
					echo "blacklist_from $id" >>/opt/zimbra/data/spamassassin/localrules/external.cf
					chown zimbra.zimbra /opt/zimbra/data/spamassassin/localrules/external.cf
					sed -i "/blacklist_from$/d" /opt/zimbra/data/spamassassin/localrules/external.cf
					sed -i "/^$/d" /opt/zimbra/data/spamassassin/localrules/external.cf
					cat /opt/zimbra/data/spamassassin/localrules/external.cf | sort | uniq >/tmp/external_uniq.txt
					cat /tmp/external_uniq.txt >/opt/zimbra/data/spamassassin/localrules/external.cf
					postcount=$(cat /opt/zimbra/data/spamassassin/localrules/external.cf | wc -l )
				        if [ "$precount" != "$postcount" ];then
						su - zimbra -c "/opt/zimbra/bin/zmamavisdctl restart ";fi
					 var=1
					 echo "$id added in blacklist zone $var"
				fi


#######################
echo "****Date:$DATE1 Time:$TIME;${bold}$count;$id${normal} is closed/black_listed ****$precount;$postcount " >>$OUTPUT
echo "****Date:Time:$TIME;${bold}$count;$id${normal} is closed/black_listed **** ">> /allclosed.txt
var=1 # Signal to send information mail abount user are trapped and mails/accounts status moved.
     
    	   fi

      else
                   echo "Everything is fine"   
		   ##### Recheck this within 15 sec again.

     fi
     ##### Recheck this within 15 sec again.
     #/usr/bin/sh /post_smart_screen.sh &    

done<$MESSAGE
cat $MESSAGE $OUTPUT > $SEND_MAIL
echo "$id added in blacklist/disabled zone $var"
	if [ $var == 1 ]
		then
                awk 'BEGIN{print "Subject:*Smart screen spam detection! Server Report*|MTA1|* !\nFrom:noreply <report@sahara.in>"}{printf("%s\015\n", $0)}' $SEND_MAIL | /opt/zimbra/common/sbin/sendmail -t "spammonitpring@sahara.in"

>$SEND_MAIL # truncate attachment file for further process.
	fi
systemctl stop iptables
echo "test passed"
fi
