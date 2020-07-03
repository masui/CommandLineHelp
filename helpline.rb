#!/usr/bin/env ruby
# -*- ruby -*-

require 'json'
require 'optparse'

require 'scrapbox'
require 're_expand'

require 'io/console'
require './curses'

puts

class HelpLine
  LINES = 12
    
  def datafile
    File.expand_path("~/.helpline")
  end
  
  def initialize
    @pagedata = {}
    @project = Scrapbox::Project.new("HelpLine")
  end

  def getdata
    #
    # ページデータ取得
    #
    puts "-----------------ページデータを取得"
    @project.pages.each { |title,page|
      puts "...#{title}"
      @pagedata[title] = page.text.split(/\n/)
    }

    dumpdata = {}
    dumpdata['codes'] = []
    dumpdata['defs'] = []
    dumpdata['pages'] = []
    
    #
    # 関数/定数を評価"
    #
    puts "-----------------関数/定数を取得"
    @pagedata.each { |title,pagedata|
      puts "...#{title}"
      pagedata. each { |line|
        if line =~ /code:(.*\.rb)$/ then
          src = $1
          puts "=========== #{src}"
          page = Scrapbox::Page.new(@project,title)
          dumpdata['codes'] << page.code(src)
        end
      }
    }
    puts "-----------------HelpLineデータを検出"
    @pagedata.each { |title,pagedata|
      puts "...#{title}"
      dumpdata['pages'] << title
      processing_defs = false
      codeindent = nil
      pagedata.each { |line|
        if !codeindent
          if line =~ /^(\s*)code:/
            codeindent = $1.length
            next
          end
        else
          line =~ /^(\s*)/
          if line.length < codeindent
            codeindent = nil
          else
            next
          end
        end
        if line =~ /^\s*[\$\%]/
          puts line
          if line =~ /^\%/ && !processing_defs
            puts "'$'で始まる用例定義なしでコマンドを定義しようとしています"
            exit
          end
          dumpdata['defs'] << "#{line} {#{dumpdata['pages'].length-1}}"
          processing_defs = true
        else
          processing_defs = false
        end
      }
    }
    
    File.open(datafile,"w"){ |f|
      f.puts dumpdata.to_json
    }
  end

  def disp(list,sel)
    Curses.move(0,0)
    lines = list.length
    lines = LINES if lines > LINES
    (0...lines).each { |i|
      Curses.move(i,0)
      s = "[#{i}] #{list[i][0]}"
      if i == sel
        Curses.print_inverse s
      else
        Curses.print s
      end
    }
    Curses.down
    Curses.tol
  end
  
  def helpline
    data = JSON.parse(File.read(datafile))
    unless data['pages'] # データ型式変換があったので
      getdata
      data = JSON.parse(File.read(datafile))
    end

    #
    # 関数定義などをeval
    #
    data['codes'].each { |code|
      eval code
    }

    g = ExpandRuby::Generator.new # re_expandのジェネレータ

    #
    # HelpLineエントリ
    #
    lines = []
    data['defs'].each { |line|
      if line =~ /^\s*\$\s*(.*)$/ # $....
        lines << $1
      elsif line =~ /^\s*\%\s*(.*)$/ # %....
        cmd = $1
        lines.each { |l|
          desc = eval('"' + l + '"')
          g.add desc.force_encoding('utf-8'), cmd.force_encoding('utf-8')
        }
        lines = []
      end
    }

    # puts "GENERATE #{params.split('|').join(' ')} "

    res = g.generate " #{ARGV.join(' ').sub(/\[/,'').sub(/\]/,'')} "

    if res[0].length == 0
      puts "ヘルプがみつかりません"
      File.open("/tmp/helpline","w"){ |f|
        f.puts ARGV.join(' ')
      }
      exit
    end

    listed = {}
    list = res[0].find_all { |a| # 0 ambig
      # a = ["現在の状況を表示する {56}", "git status {56}"], etc.
      if listed[a[1]]
        false
      else
        listed[a[1]] = true
      end
    }

    #
    # HelpLineメニュー表示し、カーソル移動で選択
    #
    
    help_number = {}
    list.each_with_index { |entry,ind|
      entry[0].sub!(/\s*{(\d*)}$/,'')
      entry[1].sub!(/\s*{(\d*)}$/,'')
      help_number[entry[0]] = $1.to_i
    }

    sel = 0
    disp(list,sel)
    
    inputchars = ''
    while true
      c = STDIN.getch
      inputchars += c
      
      if inputchars == "\e"
      # process ESC
      elsif inputchars[0] == "\e" && inputchars.length == 2
      # 何もしない
      elsif inputchars == "\x06" || inputchars == "\e[C" || inputchars == "\eOC"
        #  Curses.right
        inputchars = ''
      elsif inputchars == "\x02" || inputchars == "\e[D" || inputchars == "\eOD"
        #  Curses.left
        inputchars = ''
      elsif inputchars == "\x0e" || inputchars == "\e[B" || inputchars == "\eOB"
        Curses.down
        sel = (sel + 1) if sel < LINES-1
        inputchars = ''
      elsif inputchars == "\x10" || inputchars == "\e[A" || inputchars == "\eOA"
        Curses.up
        sel = sel - 1 if sel > 0
        inputchars = ''
      else
        inputchars = ''
      end
      STDIN.flush
      disp(list,sel)
      
      exit if c== 'q' || c == "\x03"

      if c == "\r" || c == "\n"
        break
      end
    end

    desc = list[sel.to_i][0]
    cmd = list[sel][1]

    Curses.print_inverse("「#{desc}」を実行")
    puts " (ソース: http://scrapbox.io/HelpLine/#{data['pages'][help_number[desc]]})"
    File.open("/tmp/helpline","w"){ |f|
      f.puts cmd
    }
  end
end

# is_repository = system 'git rev-parse --git-dir > /dev/null >& /dev/null'
# unless is_repository
#   STDERR.puts "Gitレポジトリで実行して下さい"
#   exit
# end

options = ARGV.getopts('u')

helpline = HelpLine.new

if !File.exist?(helpline.datafile) && !options['u']
  puts "#{helpline.datafile}を作成します..."
  helpline.getdata
end
  
if options['u'] then
  helpline.getdata
else  
  helpline.helpline
end
