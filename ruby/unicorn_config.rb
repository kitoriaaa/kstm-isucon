worker_processes 4
preload_app true
pid './unicorn.pid'
listen 8080

stderr_path File.expand_path('../../log/unicorn_stderr.log', __FILE__)
stdout_path File.expand_path('../../log/unicorn_stdout.log', __FILE__)
