A batched bulk processing library implemented using active_record (with mysql) and sidekiq.

the idea is to have all the data staged in a table and process them in a batched fashion. the batches are processed in parallel. we specify max parallelism and batch size.

we handle concurrency using the database. all coordination is done via database locks

has per record status tracking and retry mechanism built into the algorithm with the ability to control how many times we must attempt processing a record.

NOTE: this is not a production ready library. the core algorithm is solid and can be directly take to production but the gem requires to be hardened and polished furuther

the logic is as below

* stage records into the records table
* initiate a planner job
* planner creates batches (fixed number at a time) and enqueues processor jobs to work on the batches in parallel
* waits for all the already created batches to be completed and icrementally creates more batches till all records are covered
* when on pass is completed, the planner checks for errors and starts the same process again from the top for the failed records

the processor_class should support initialization with new without parameters and the instance must respond to #process method that accepts one mandatory parameter (record data column value)

the sidekiq jobs must be able to load the processor_class


if the lib is present at /path/to/lib then

to start irb with the library required
```shell
cd /path/to/lib
host=localhost username=root password= database=myapp irb  -Ilib -rmassive-import
```

to run the sidekiq server
```shell
cd /path/to/lib
host=localhost username=root password= database=myapp sidekiq -r ./boot_sidekiq.rb -c 20
```

to run the built-in massive-import dashboard
```shell
cd /path/to/lib
dashboard_host=127.0.0.1 dashboard_port=9292 host=localhost username=root password= database=myapp ruby ./boot_dashboard.rb
```

the dashboard
  shows list of imports (path: '/')
  specific import (path: '/imports/:import_id')

both routes accept a refresh query param to specify auto refresh
eg. localhost:9292?refresh=2, localhost:9292/imports/99?refresh=5

to run sidekiq dashboard
```shell
cd /path/to/lib
rackup -p 9293
```

to start a demo import, run the following in irb after loading the library
NOTE: DemoProcessor is defined in boot_sidekiq.rb
```ruby

# uncomment if you want a clean slate
# MassiveImport::Record.delete_all
# MassiveImport::Batch.delete_all
# MassiveImport::Import.delete_all

import = MassiveImport::Import.create(
  processor_class: 'DemoProcessor',
  batch_size: 2,
  max_attempts: 3,
  max_batch_concurrency: 5
)

records = []
100.times do
  records << Array.new(5) { [rand(1..10), rand(1..10)] }.to_h
end

MassiveImport.stage_records(import, records)

```