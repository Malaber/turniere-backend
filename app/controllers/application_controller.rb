# frozen_string_literal: true

class ApplicationController < ActionController::API
  include DeviseTokenAuth::Concerns::SetUserByToken

  around_action :record_request_metrics
  before_action :configure_permitted_parameters, if: :devise_controller?

  rescue_from ActionController::ParameterMissing do |e|
    render json: { error: e.message }, status: :bad_request
  end
  rescue_from ActiveRecord::RecordInvalid, with: :render_record_invalid_error
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found_error

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:username])
    devise_parameter_sanitizer.permit(:account_update, keys: [:username])
  end

  private

  def record_request_metrics
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    metrics_status = nil
    yield
  rescue StandardError => e
    metrics_status = ActionDispatch::ExceptionWrapper.status_code_for_exception(e.class.name)
    raise
  ensure
    MetricsRegistry.record_http_request(
      method: request.request_method,
      controller: controller_path,
      action: action_name,
      status: metrics_status || response.status,
      duration: Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    )
  end

  def require_owner!(owner)
    render_forbidden_error if owner != current_user
  end

  def render_forbidden_error
    render json: {
      errors: [
        'Only the parent tournament owner can update this resource'
      ]
    }, status: :forbidden
  end

  def render_read_only_error
    render json: {
      error: 'Tournament is in read only follower mode'
    }, status: :locked
  end

  def require_writable_tournament!(tournament)
    render_read_only_error if tournament&.read_only_mode?
  end

  def render_not_found_error(exception)
    error = if exception.is_a?(ActiveRecord::RecordNotFound) && exception.model.present?
              "Couldn't find #{exception.model} with '#{exception.primary_key}'=#{exception.id.inspect}"
            else
              'Record not found'
            end
    render json: { error: error }, status: :not_found
  end

  def render_record_invalid_error(exception)
    render json: exception.record.errors, status: :unprocessable_content
  end
end
