require "simple_abs/version"

module SimpleAbs

  def is_bot?
    agent = request.env["HTTP_USER_AGENT"]
    matches = nil
    matches = agent.match(/(facebook|postrank|voyager|twitterbot|googlebot|slurp|butterfly|pycurl|tweetmemebot|metauri|evrinid|reddit|digg|yandexbot|stackrambler|mail.ru|pinterest|curl|bingbot|baidu|duckduckgo|proximic|sogou|360spider)/mi) if agent
    if (agent.nil? or matches)
      return true
    else
      return false
    end
  end

  def increment(experiment, which, field)
    condition = ["experiment = '%s' AND which = '%s'", experiment, which]
    sanitized_condition = SimpleAbs::Alternative.send(:sanitize_sql_for_conditions, condition)

    query = <<-SQL.squish
      UPDATE alternatives SET #{field} = #{field} + 1
      WHERE #{sanitized_condition}
    SQL

    ActiveRecord::Base.connection.exec_query query
  end

  def ab_test(name, tests)
    alternatives = tests.map { |t| t.is_a?(Hash) ? t : { t => 1 } }

    return choose_alternative(alternatives) if is_bot?
    return params[:test_value] if params[:test_value]

    test_value = cookies[name]

    if test_value.blank? || !alternatives.map { |a| a.keys.first }.include?(test_value)
      test_value = choose_alternative(alternatives)
      cookies.permanent[name] = test_value

      alternative = find_or_create_by_experiment_and_which_method(name, test_value)
      increment(name, test_value, :participants)
    end

    return test_value
  end

  def participate_in_test(name, test_value)
    return if is_bot? || cookies[name].present?
    cookies.permanent[name] = test_value
    find_or_create_by_experiment_and_which_method(name, test_value)
    increment(name, test_value, :participants)
  end

  def choose_alternative(tests)
    weights = tests.map { |test| test.values.first }

    total = weights.inject(:+)
    point = rand * total

    tests.zip(weights).each do |test, weight|
      return test.keys.first if weight >= point
      point -= weight
    end
  end

  def converted!(name)
    if !is_bot?
      test_value = cookies[name]
      if test_value && cookies[name.to_s + "_converted"].blank?
        alternative = find_or_create_by_experiment_and_which_method(name, test_value)
        increment(name, test_value, :conversions)
        cookies.permanent[name.to_s + "_converted"] = true
      end
    end
  end

  def find_or_create_by_experiment_and_which_method(experiment, which)
    alternative = Alternative.where(experiment: experiment, which: which).first

    if alternative.nil?
      alternative = Alternative.new
      alternative.experiment = experiment
      alternative.which = which
      alternative.save
    end

    return alternative
  end


  class Railtie < Rails::Railtie

    initializer "simple_abs.initialize" do
      ActionView::Base.send :include, SimpleAbs
      ActionController::Base.send :include, SimpleAbs
    end

  end

  class Alternative < ActiveRecord::Base

    def conversion
      if participants.present? && conversions.present?
        (participants.to_f/conversions.to_f).round(2)
      end
    end

    # 90 percent error
    def error

    end

  end


end
