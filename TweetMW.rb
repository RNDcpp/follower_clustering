# encoding: utf-8
require 'twitter'
require 'natto'
require 'sqlite3'
require 'pp'
require 'yaml'

class WordDB
  def initialize()
    @level = 0
    @user_list=Array.new
    @nat = Natto::MeCab.new
    @db=SQLite3::Database.new "user-word.db"
    @db.execute("drop table if exists users")
    @db.execute("drop table if exists words")
    @db.execute("drop table if exists counts")
    @db.execute("drop table if exists classes")
    @db.execute("drop table if exists distance")
    @db.execute("create table users(name varchar(32),fname varchar(64))")
    @db.execute("create table words(surface varchar(32))")
    @db.execute("create table counts(uid int,wid int,cnt int)")
    @db.execute("create table classes(uid int,cid_a int,cid_b int,level int)")
    @db.execute("create table distance(uid_a int,uid_b int,distance int)")
  end
  def get_wid(surface)
    re=@db.execute('select rowid from words where surface = ?',surface).first
    re=re[0] if re
    re
  end
  def get_uid(name)
    re=@db.execute('select rowid from users where name = ?',name).first
    re=re[0] if re
    re
  end
  def add_wid(surface)
    @db.execute('insert into words(surface) values(?)',surface)
  end
  def add_uid(name,fname)
    re=@db.execute('insert into users(name,fname) values(?,?)',[name,fname])
    @user_list.push(get_uid(name))
    re
  end
  def get_cnt(user,word)
    re=@db.execute('select cnt from counts where uid = ? and wid = ?',[get_uid(user),get_wid(word)]).first
    re=re[0] if re
    re
  end

  def get_cnt_by_id(uid,wid)
    re=@db.execute('select cnt from counts where uid = ? and wid = ?',[uid,wid]).first
    re=[0,0] unless re
    re[0]
  end
  def delete_word
    all=@db.execute("select sum(cnt) from counts").first[0]
    @db.execute("select rowid from words").each do |wid|
      p pol=@db.execute("select sum(cnt) from counts where wid = ?",wid[0]).first[0]
      if pol.to_f/all < 0.005 or pol.to_f/all > 0.5
        @db.execute("delete from counts where wid = ?",wid[0])
        pp @db.execute("select surface from words where rowid = ?",wid[0])
      end
    end
  end
  def  get_distance(uid1,uid2)
    dist=0
    puts "get_distance #{uid1} #{uid2}"
    @db.execute('select wid from counts where uid = ? union select wid from counts where uid = ?',[uid1,uid2]).each do |wid|
      #puts "wid:#{wid} :calc_dist_word"
      dist+=(get_cnt_by_id(uid1,wid[0])-get_cnt_by_id(uid2,wid[0]))**2
    end
    dist = Math.sqrt(dist)
    unless @db.execute('select * from distance where (uid_a=? and uid_b=?) or (uid_b=? and uid_a=?)',[uid1,uid2,uid1,uid2]).first
      puts"RECORD DISTANCE"
      @db.execute('insert into distance(uid_a,uid_b,distance) values(?,?,?)',[uid1,uid2,dist])
    end
    puts dist
    dist
  end

  def add_new_class(uid1,uid2)
    puts"add new class#{@level}"
    class_name="class#{@level}"
    add_uid(class_name,class_name)
    uid = get_uid(class_name)
    @user_list.delete(uid1)
    @user_list.delete(uid2)
    @db.execute('insert into classes(uid,cid_a,cid_b,level) values(?,?,?,?)',[uid,uid1,uid2,@level])
    @db.execute('select wid from counts where uid = ? union select wid from counts where uid = ?',[uid1,uid2]).each do |wid|
      cnt=(get_cnt_by_id(uid1,wid[0])+get_cnt_by_id(uid2,wid[0]))/2
      @db.execute('insert into counts(uid,wid,cnt) values(?,?,?)',[uid,wid,cnt])
    end
    @db.execute('select rowid from users where name != ?',class_name).each do |user_t|
      get_distance(user_t[0],uid) if @user_list.include?(user_t[0])
    end
    pp @user_list
    @level+=1
  end

  def get_close_pair
    pp @user_list
    @db.execute('select * from distance order by distance asc').each do |pair|
      return pair if @user_list.include?(pair[0]) and @user_list.include?(pair[1])
    end
  end

  def get_all_distance
    @db.execute('select rowid from users').each do |wid|
      pp id = wid[0]
      for num in 1...id
        get_distance(num,id)
      end
    end
  end
  def over?
    @user_list.length <= 1
  end
  def cnt(word)
    word_hash = {}
#   p word.length
    word.each do |e|
      @nat.parse(e) do |n|
        if(n.feature.match(/(名詞)/)) and /[^!-@\[-`{-~　「」a-z]/ =~ n.surface and (n.surface.length>1)  # 数字/記号以外を含む名詞のみカウントする
	  word_hash[n.surface]||=0
          word_hash[n.surface]+=1
        end
      end
    end
    return word_hash
  end

  def cnt_save(user_name,name,docs)
    add_uid(user_name,name) unless get_uid(user_name)
    puts "UID=#{uid = get_uid(user_name)}"
    word_hash=cnt(docs)
    word_hash.each do |word,cnt|
      add_wid(word) unless get_wid(word)
      wid = get_wid(word)
      @db.execute('insert into counts(uid,wid,cnt) values(?,?,?)',[uid,wid,cnt])
      #puts "insert #{word}:#{cnt}"
      get_cnt(user_name,word)
    end
  end
end
class TClient
  @client
  @newest_mention
  def initialize()
    key = YAML.load_file 'config.yml'
    @client = Twitter::REST::Client.new do |config|
      config.consumer_key        = key['consumer_key']
      config.consumer_secret     = key['consumer_secret']
      config.access_token        = key['api_key']
      config.access_token_secret = key['api_secret']
    end	
  end
  def get_tweet(user,rep=1)
    results=[]
    max_id=nil
    for num in 0..1
      begin
        @client.user_timeline(user,{"count"=>200}).each do |t|
          unless /^RT / =~ t.text
            results.push(t.text) 
          end
          max_id=t.id	
        end
      rescue Twitter::Error::TooManyRequests => error
        puts"TooManyRequests"
        sleep error.rate_limit.reset_in + 1
        retry
      end
    end
    return results	
  end
  def get_followers
    begin
      followers=@client.followers
    rescue Twitter::Error::TooManyRequests => error
      puts"TooManyRequests"
      sleep error.rate_limit.reset_in + 1
      retry
    end
    puts"get followers" if followers
    return followers
  end
end
class FollowerCluster
  def initialize
    @tc=TClient.new
    @wdb=WordDB.new
  end
  def run
    puts'start run'
    followers=@tc.get_followers 
    followers.each do |user|
      pp user
      @wdb.add_uid user.screen_name,user.name
      puts 'get followers'
      docs = @tc.get_tweet(user.id,1)
      @wdb.cnt_save(user.screen_name,user.name,docs)
    end
    @wdb.delete_word
    puts "get all distance"
    @wdb.get_all_distance
    puts "clustering"
    until @wdb.over?
      puts "closest pair"
      pp pair=@wdb.get_close_pair
      @wdb.add_new_class(pair[0],pair[1])
    end
  end
end
tmr=FollowerCluster.new
tmr.run
