# call with "GET /cpu/<d> HTTP/1.1\r\n\r\n", where <d> is the number of
# seconds to spin CPU, returns process pid

def cpu_threadtime
  # Not all OS kernels are supporting `Process::CLOCK_THREAD_CPUTIME_ID`
  # Refer: https://gitlab.com/gitlab-org/gitlab/issues/30567#note_221765627
  return unless defined?(Process::CLOCK_THREAD_CPUTIME_ID)

  Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID, :float_second)
end

run lambda { |env|
  duration_s = (env['REQUEST_PATH'][/\/cpu\/(\d.*)/,1] || '1').to_f

  expected_end_time = cpu_threadtime + duration_s
  rand while cpu_threadtime < expected_end_time

  [200, {"Content-Type" => "text/plain"}, ["Run for #{duration_s} #{Process.pid}"]]
}
