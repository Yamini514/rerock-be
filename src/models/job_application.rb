class App::Models::JobApplication < Sequel::Model
  many_to_one :job_opening
end
