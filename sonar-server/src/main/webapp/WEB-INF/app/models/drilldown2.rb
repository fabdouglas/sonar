#
# Sonar, open source software quality management tool.
# Copyright (C) 2008-2012 SonarSource
# mailto:contact AT sonarsource DOT com
#
# Sonar is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 3 of the License, or (at your option) any later version.
#
# Sonar is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with Sonar; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02
#
class Drilldown2

  DEFAULT=[['TRK'], ['BRC'], ['DIR', 'PAC'], ['FIL', 'CLA', 'UTS']]
  VIEWS=[['VW'], ['SVW'], ['TRK']]
  PERSONS=[['PERSON'], ['PERSON_PRJ']]
  TREES=[DEFAULT, VIEWS, PERSONS]

  def self.qualifier_children(q)
    return [] if q==nil
    TREES.each do |tree|
      tree.each_with_index do |qualifiers, index|
        if qualifiers==q || qualifiers.include?(q)
          return index+1<tree.size ? tree[index+1] : []
        end
      end
    end
    []
  end


  attr_reader :resource, :metric, :selected_resource_ids
  attr_reader :snapshot, :columns, :highlighted_resource, :highlighted_snapshot

  def initialize(resource, metric, selected_resource_ids, options={})
    @resource=resource
    @selected_resource_ids=selected_resource_ids||[]
    @metric=metric
    @snapshot=resource.last_snapshot
    @columns=[]

    if @snapshot
      column=DrilldownColumn2.new(self, nil)
      while column.valid?
        column.init_measures(options)
        @columns<<column if column.display?
        column=DrilldownColumn2.new(self, column)
      end
    end
  end

  def display_value?
    ProjectMeasure.exists?(["snapshot_id=? and metric_id=? and value is not null", @snapshot.id, @metric.id])
  end

  def display_period?(period_index)
    ProjectMeasure.exists?(["snapshot_id=? and metric_id=? and variation_value_#{period_index.to_i} is not null", @snapshot.id, @metric.id])
  end
end


class DrilldownColumn2

  attr_reader :measures, :base_snapshot, :selected_snapshot, :qualifiers, :person_id

  def initialize(drilldown, previous_column)
    @drilldown = drilldown

    if previous_column
      @base_snapshot=(previous_column.selected_snapshot || previous_column.base_snapshot)
      @person_id=(previous_column.person_id || @base_snapshot.resource.person_id)
    else
      @base_snapshot=drilldown.snapshot
      @person_id=@base_snapshot.resource.person_id
    end

    # switch
    if @base_snapshot.resource.copy
      @base_snapshot=@base_snapshot.resource.copy.last_snapshot
      @qualifiers = Drilldown2.qualifier_children(@base_snapshot.qualifier)

    elsif previous_column
      @qualifiers=Drilldown2.qualifier_children(previous_column.qualifiers)

    else
      @qualifiers=Drilldown2.qualifier_children(drilldown.snapshot.qualifier)
    end

    @resource_per_sid={}
  end

  def init_measures(options)
    value_column = (options[:period] ? "variation_value_#{options[:period]}" : 'value')
    order="project_measures.#{value_column}"
    if @drilldown.metric.direction<0
      order += ' DESC'
    end

    conditions="snapshots.root_snapshot_id=:root_sid AND snapshots.islast=:islast AND snapshots.qualifier in (:qualifiers) " +
      " AND snapshots.path LIKE :path AND project_measures.metric_id=:metric_id AND project_measures.#{value_column} IS NOT NULL"
    condition_values={
      :root_sid => (@base_snapshot.root_snapshot_id || @base_snapshot.id),
      :islast => true,
      :qualifiers => @qualifiers,
      :metric_id => @drilldown.metric.id,
      :path => "#{@base_snapshot.path}#{@base_snapshot.id}.%"}

    if value_column=='value' && @drilldown.metric.best_value
      conditions<<' AND project_measures.value<>:best_value'
      condition_values[:best_value]=@drilldown.metric.best_value
    end

    if options[:exclude_zero_value]
      conditions += " AND project_measures.#{value_column}<>0"
    end

    if options[:rule_id]
      conditions += ' AND project_measures.rule_id=:rule'
      condition_values[:rule]=options[:rule_id]
    else
      conditions += ' AND project_measures.rule_id IS NULL '
    end

    if options[:characteristic]
      conditions += ' AND project_measures.characteristic_id=:characteristic_id'
      condition_values[:characteristic_id]=options[:characteristic].id
    else
      conditions += ' AND project_measures.characteristic_id IS NULL'
    end

    if @person_id
      conditions += ' AND project_measures.person_id=:person_id'
      condition_values[:person_id]=@person_id
    else
      conditions += ' AND project_measures.person_id IS NULL'
    end

    @measures=ProjectMeasure.find(:all,
                                  :select => "project_measures.id,project_measures.metric_id,project_measures.#{value_column},project_measures.text_value,project_measures.alert_status,project_measures.alert_text,project_measures.snapshot_id",
                                  :joins => :snapshot,
                                  :conditions => [conditions, condition_values],
                                  :order => order,
                                  :limit => 200)

    @resource_per_sid={}
    sids=@measures.map { |m| m.snapshot_id }.compact.uniq
    unless sids.empty?
      Snapshot.find(:all, :include => :project, :conditions => {'snapshots.id' => sids}).each do |snapshot|
        @resource_per_sid[snapshot.id]=snapshot.project
        if @drilldown.selected_resource_ids.include?(snapshot.project_id)
          @selected_snapshot=snapshot
        end
      end
    end
  end

  def resource(measure)
    @resource_per_sid[measure.snapshot_id]
  end

  def display?
    @measures && !@measures.empty?
  end

  def valid?
    @base_snapshot && @qualifiers && !@qualifiers.empty?
  end
end