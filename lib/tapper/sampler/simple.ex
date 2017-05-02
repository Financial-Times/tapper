defmodule Tapper.Sampler.Simple do

  def sample() do
    # sample 10%
    :rand.uniform(10) == 1
  end

end