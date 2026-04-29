# frozen_string_literal: true

class MetricsController < ApplicationController
  def index
    render plain: MetricsRegistry.render_prometheus,
           content_type: 'text/plain; version=0.0.4'
  end
end
