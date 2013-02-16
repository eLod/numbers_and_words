require "bundler/setup"

def git_initialize repository
  unless File.exist?(".git")
    system "git init"
    system "git remote add origin git@github.com:#{repository}.git"
  end
end

def git_update
  system "git fetch origin"
  if `git branch -r` =~ /gh-pages/
    system "git reset --hard origin/gh-pages"
  else
    system "git checkout master"
    system "git checkout --orphan gh-pages"
  end
end

desc "Deploy the website to github pages"
task :deploy do
  head = `git log --pretty="%h" -n1`.strip
  message = "Site generated for #{head}."

  mkdir_p "build"
  Dir.chdir "build" do
    git_initialize "eLod/numbers_and_words"
    git_update

    system "middleman build -c"

    system "git add -A"
    system "git commit -m '#{message}'"
    system "git push origin gh-pages"
  end
end
