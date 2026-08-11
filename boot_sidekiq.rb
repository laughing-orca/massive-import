require "bundler/setup"
require "massive-import"

class DemoProcessor
  def process(data)
    sleep rand(2..5)

    r = rand(1..10)
    case 
    when r % 2 == 0
      'COMPLETED'
    when r % 3 == 0
      'ERROR'
    else
      'INVALID'
    end
  end
end
