@ECHO OFF
SET QUEUE=*
SET RAILS_ENV=production
bundle exec rake resque:work