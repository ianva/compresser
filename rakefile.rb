require 'pathname'
require "iconv" 
require 'yaml'

class String
	def utf8!
		%w(ascii-8bit utf-8 ucs-bom shift-jis gb18030 gbk gb2312 cp936).any? do |c|
			begin
				if self.respond_to? :encode
					self.encode!('utf-8', c).force_encoding('utf-8')
				else
					require 'iconv'
					text = Iconv.new('UTF-8', c).iconv(self)
				end
				if self =~ /./
					$enc = c
					return self
				end
			rescue
			end
		end
		self
	end
end


config = YAML.load_file("config.yml")

COMPRESSOR_PATH = config["path"]["yuicompressor"]
PROJECT_PATH = config["path"]["project"]
TYPE = config["type"]
CHARSET = config["charset"]
POSTFIX = config["postfix"]
MERGE = config["merge"]

# 合并文件
def merge_file merge_info,root_path
	merge_info.each do |info|
		name = info["new"]
		paths = info["paths"].map{|src| 
			src = root_path+"/"+src 
		}
		text = ""
		FileList[*paths].each do |src|
			unless File.directory? src
				File.open(src,"rb") do |f|
					text << f.read.gsub(/\r\n/,'\n').gsub(/\r/,'\n')
				end
			end
		end
		
		File.open(root_path+"/"+name,"wb") do |f|
			f << text
		end	
	end
end
# 获取所有路径
def get_paths path, type  
	paths = []
	unless path.class.to_s == "Array"
		Array(type).each{|item|
			paths << path+"/**/*."+item
		}
	else
		paths == path
	end
    paths
end
# 压缩文件
def compress paths,postfix,type,charset
	#puts paths
	FileList[*paths].each do |src|
		path =  Pathname.new(src)
	   	dirname = path.dirname
		type = path.extname[/[^.]+$/]	
		name = (path.basename.to_s.gsub("."+type,"")).to_s
		text = ""
		unless !!(/#{postfix}$/=~name)	
			out_src = "#{dirname + name}#{postfix}.#{type}"
			text = `java -jar #{COMPRESSOR_PATH} --type #{type} --charset utf-8 #{src} `.encode(charset,"utf-8").force_encoding charset
			File.open(out_src,"w",{:encoding=>charset}) do |f|
				#puts f.path
				f << text
			end
		end
	end
end   

namespace :min do
	# 压缩修改的文件
	task :a do
		merge_file MERGE,PROJECT_PATH
		paths = get_paths PROJECT_PATH,TYPE
		compress paths,POSTFIX,TYPE,CHARSET
	end
	# 压缩变更的文件(包括修改及添加)	
	task :c do
		svn_paths = `svn status #{PROJECT_PATH}`
		modify_paths = []
		merage_info = []
		svn_paths.lines{|item|
			# 从 svn 中解析出修改及添加过的文件路径
			if /^[M?]\s*(?<path>[^\s]+\.(?<type>#{TYPE.join("|")})$)/ =~ item 
				path = $~["path"]
				type = $~["type"]
				# 过滤压缩文件
				unless !!(/#{POSTFIX}.#{type}$/ =~ path)
					modify_paths <<  path
				end
				
				# 找出修改后需要合并的文件
				Array(MERGE).each do |info| 
					src = info["paths"].collect{|path| PROJECT_PATH + "/" + path }	
					if src.include? path
						merage_info << info
						modify_paths << PROJECT_PATH + "/" + info["new"]
					end
				end
			end
		}
		puts "=begin", "compress files:", modify_paths, "=end"
		merge_file merage_info,PROJECT_PATH
		compress modify_paths,POSTFIX,["js","css"],CHARSET
	end
end

