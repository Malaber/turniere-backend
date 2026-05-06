# frozen_string_literal: true

class AdvanceTeamsInIntermediateStage
  include Interactor

  def call
    intermediate_stage = context.intermediate_stage
    return if intermediate_stage.nil?

    # shuffle positions of generated matches to spread the instantly advancing teams across the tournament tree
    matches = intermediate_stage.matches
    matches.shuffle.each_with_index do |m, i|
      m.position = i
      m.save!
    end

    # populate stage below with the "winners" from single team matches
    matches.select { |m| m.state == 'single_team' }
           .each do |match|
      context.fail! unless PopulateMatchBelowAndSave.call(match:).success?
    end
    (context.object_to_save ||= []) << intermediate_stage
  end
end
