# encoding: utf-8
require 'natto'
require 'redis'
require 'pp'

module WordMatch
  extend self
  @@nat = Natto::MeCab.new
  @@word_past = Hash.new
  @@word_past['s'] = ''
  @@word_past['f'] = ''
  def cnt(documents)
    word_hash = Hash.new
    terms_count = 0
    documents.each do |e|
      @@nat.parse(e) do |word|
        if /[^!-@\[-`{-~　「」]/ =~ word.surface
          if (word.feature.match(/(形容詞|形容動詞)/)) and (word.surface.length>1)
            word_f = word.surface
            word_hash[word_f]||=0
            word_hash[word_f]+=1
            terms_count+=1
          end
        end
        if((word.surface == 'ない')and(@@word_past['f'].match(/(形容詞)/)))
          word_f = @@word_past['s']+word.surface
          word_hash[word_f]||=0
          word_hash[word_f]+=1         
        end
        @@word_past['s'] = word.surface
        @@word_past['f'] = word.feature 
      end
    end
    p terms_count
    word_hash.each {|key,value|word_hash[key] = value.to_f/terms_count}
    return word_hash
  end
  def tfidf(tf,df,d_term_num)
    word_hash=Hash.new
    df_cpy = df.dup
    tf.each do |key,value|
      if df_cpy[key]
        df_cpy[key]=1 if df_cpy[key]==0
        word_hash[key] = value*(Math.log10(d_term_num.to_f/df_cpy[key])+1)
      end
    end
    return word_hash
  end
  def df_counts(documents)
    df = Hash.new
    documents.each do |e|
      word_hash = Hash.new
      @@nat.parse(e) do |word|
        if (word.feature.match(/(形容詞)/))
          word_hash[word.surface]=1
        end
      end
      word_hash.each_key do |key|
        df[key]||=0
        df[key]+=1
      end
    end
    return df
  end

end
