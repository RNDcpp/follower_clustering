require'sqlite3'
require'pp'
$db=SQLite3::Database.new "user-word.db"
$open_list=Array.new
$closed_list=Array.new
$data=""
def plot_tree
  cid=$open_list.last
  user=$db.execute("select * from users where rowid = ?",cid).first
  c=$db.execute("select * from classes where uid = ?",cid).first 
  if c
    if($closed_list.include?(c[2]))
      $closed_list.push(cid)
      $open_list.pop
    elsif($closed_list.include?(c[1]))
      $open_list.push(c[2])
    else
      $open_list.push(c[1])
    end
    $data+= "\n"
  else
    $data+= "#{user[1]}@#{user[0]}"
    $closed_list.push(cid)
    $open_list.pop
  end
end
$open_list.push $db.execute("select uid from classes order by level desc").first[0]
plot_tree while $open_list.last
File.write("#{ARGV[0]}",$data)
puts $data
