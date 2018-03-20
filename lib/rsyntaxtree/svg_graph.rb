#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

#==========================
# svg_graph.rb
#==========================
#
# Parses an element list into an SVG tree.
#
# This file is part of RSyntaxTree, which is a ruby port of Andre Eisenbach's
# excellent program phpSyntaxTree.
#
# Copyright (c) 2007-2018 Yoichiro Hasebe <yohasebe@gmail.com>
# Copyright (c) 2003-2004 Andre Eisenbach <andre@ironcreek.net>
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

require 'rvg/rvg'
include Magick

# constant variables are already set in tree_graph.rb

class SVGGraph
    
  def initialize(e_list, metrics, symmetrize, color, leafstyle,
                 font, fontstyle, font_size, multibyte)

    # Store parameters
    @e_list     = e_list
    @m          = metrics
    @font       = font
    @fontstyle  = fontstyle == "sans" ? "sans-serif" : fontstyle
    @font_size  = font_size
    @leafstyle  = leafstyle
    @symmetrize = symmetrize


    # Calculate image dimensions
    @e_height = @font_size + @m[:e_padd] * 2
    h         = @e_list.get_level_height
    w         = calc_level_width(0)
    w_px      = w + @m[:b_side] 
    h_px      = h * @e_height + (h-1) * (@m[:v_space] + @font_size) + @m[:b_topbot] * 2
    @height   = h_px
    @width    = w_px

    
    # Initialize the image and colors
    @col_bg   = "none"
    @col_fg   = "black"
    @col_line = "black"
    
    if color
      @col_node  = "blue"
      @col_leaf  = "green"
      @col_trace = "red"
    else
      @col_node  = "black"
      @col_leaf  = "black"
      @col_trace = "black"
    end

    @line_styles  = "<line style='stroke:black; stroke-width:1;' x1='X1' y1='Y1' x2='X2' y2='Y2' />\n"
    @polygon_styles  = "<polygon style='fill: none; stroke: black; stroke-width:1;' points='X1 Y1 X2 Y2 X3 Y3' />\n"
    @text_styles  = "<text style='fill: COLOR; font-size: FONT_SIZEpx; ST; WA;' x='X_VALUE' y='Y_VALUE' TD font-family='#{@fontstyle}'>CONTENT</text>\n"
    @tree_data  = String.new

    @sub_size = (@font_size * SUBSCRIPT_CONST )
    @sub_space_width = img_get_txt_width2("l", @fontstyle, @sub_size)
  end

  def svg_data
    parse_list
    header =<<EOD
<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" 
 "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg width="#{@width}" height="#{@height}" version="1.1" xmlns="http://www.w3.org/2000/svg">
EOD

    footer = "</svg>"
#    File.open(filename, "w") do |f|
#      f.write header
#      f.write @tree_data
#      f.write footer
#    end
    header + @tree_data + footer
  end

  # Create a temporary file and returns only its filename
  def create_tempf(basename, ext, num = 10)
    flags = File::RDWR | File::CREAT | File::EXCL
    tfname = ""
    num.times do |i|
      begin
        tfname = "#{basename}.#{$$}.#{i}.#{ext}"
        tfile = File.open(tfname, flags, 0600)
      rescue Errno::EEXIST
        next
      end
      tfile.close
      return tfname
    end
  end
  
  :private
 
  # Add the element into the tree (draw it)
  def draw_element(x, y, w, string, type)
 
    # Calculate element dimensions and position
    if (type == ETYPE_LEAF) and @leafstyle == "nothing"
      top = row2px(y - 1) + (@font_size * 1.5)
    else 
      top   = row2px(y)
    end
    left   = x + @m[:b_side]
    bottom = top  + @e_height
    right  = left + w

    parts = string.split("_", 2)
    if(parts.length > 1 )
      main = parts[0].strip
      sub  = parts[1].gsub(/_/, " ").strip
    else
      main = parts[0].strip
      sub  = ""
    end

    if /\A\+(.+)\+\z/ =~ main
      main = $1
      decoration= "overline"
    elsif /\A\-(.+)\-\z/ =~ main
      main = $1
      decoration= "underline"
    elsif /\A\=(.+)\=\z/ =~ main
      main = $1
      decoration= "line-through"
    else
      decoration= ""
    end

    if /\A\*\*\*(.+)\*\*\*\z/ =~ main
      main = $1
      style = "font-style: italic"
      weight = "font-weight: bold"
    elsif /\A\*\*(.+)\*\*\z/ =~ main
      main = $1
      style = ""
      weight = "font-weight: bold"
    elsif /\A\*(.+)\*\z/ =~ main
      main = $1
      style = "font-style: italic"
      weight = ""
    else
      style = ""
      weight = ""
    end

    main_width = img_get_txt_width2(main, @fontstyle, @font_size)

    if sub != ""
      sub_width  = img_get_txt_width2(sub.to_s,  @fontstyle, @sub_size)
    else
      sub_width = 0
    end

    # Center text in the element
    txt_width = main_width + sub_width
    txt_pos   = left + (right - left) / 2 - txt_width / 2
  
    # Select apropriate color
    if(type == ETYPE_LEAF)
      col = @col_leaf
    else
      col = @col_node      
    end
    
    if(main[0].chr == "<" && main[-1].chr == ">")
      col = @col_trace
    end

    # Draw main text
    main_data  = @text_styles.sub(/COLOR/, col)
    main_data  = main_data.sub(/FONT_SIZE/, @font_size.to_s)
    main_x = txt_pos
    main_y = top + @e_height - @m[:e_padd]
    main_data  = main_data.sub(/X_VALUE/, main_x.to_s)
    main_data  = main_data.sub(/Y_VALUE/, main_y.to_s)

    @tree_data += main_data.sub(/TD/, "text-decoration='#{decoration}'")
                           .sub(/ST/, style)
                           .sub(/WA/, weight)
                           .sub(/CONTENT/, main)
    # Draw subscript text
    sub_data  = @text_styles.sub(/COLOR/, col)
    sub_data  = sub_data.sub(/FONT_SIZE/, @sub_size.to_s)
    sub_x = main_x + main_width + @sub_space_width
    sub_y = top + (@e_height - @m[:e_padd] + @sub_size / 2).ceil
    if (sub.length > 0 )
      sub_data   = sub_data.sub(/X_VALUE/, sub_x.ceil.to_s)
      sub_data   = sub_data.sub(/Y_VALUE/, sub_y.ceil.to_s)
      @tree_data += sub_data.sub(/TD/, "")
                    .sub(/ST/, "")
                    .sub(/WA/, "")
                    .sub(/CONTENT/, sub)
    end
  end

  # Draw a line between child/parent elements
  def line_to_parent(fromX, fromY, fromW, toX, toW)

    if (fromY == 0 )
      return
    end
            
    fromTop  = row2px(fromY)
    fromLeft = (fromX + fromW / 2 + @m[:b_side])
    toBot    = (row2px(fromY - 1 ) + @e_height)
    toLeft  = (toX + toW / 2 + @m[:b_side])

    line_data   = @line_styles.sub(/X1/, fromLeft.ceil.to_s.to_s)
    line_data   = line_data.sub(/Y1/, fromTop.ceil.to_s.to_s)
    line_data   = line_data.sub(/X2/, toLeft.ceil.to_s.to_s)
    @tree_data += line_data.sub(/Y2/, toBot.ceil.to_s.to_s)

  end

  # Draw a triangle between child/parent elements
  def triangle_to_parent(fromX, fromY, fromW, toW, textW, symmetrize = true)
    if (fromY == 0)
      return
    end
          
    toX = fromX
    fromCenter = (fromX + fromW / 2 + @m[:b_side])
    
    fromTop  = row2px(fromY).ceil
    fromLeft1 = (fromCenter + textW / 2).ceil
    fromLeft2 = (fromCenter - textW / 2).ceil
    toBot    = (row2px(fromY - 1) + @e_height)

    if symmetrize
      toLeft   = (toX + textW / 2 + @m[:b_side])
    else
      toLeft   = (toX + textW / 2 + @m[:b_side] * 3)
    end
        
    polygon_data = @polygon_styles.sub(/X1/, fromLeft1.ceil.to_s)
    polygon_data = polygon_data.sub(/Y1/, fromTop.ceil.to_s)
    polygon_data = polygon_data.sub(/X2/, fromLeft2.ceil.to_s)
    polygon_data = polygon_data.sub(/Y2/, fromTop.ceil.to_s)
    polygon_data = polygon_data.sub(/X3/, toLeft.ceil.to_s)
    @tree_data  += polygon_data.sub(/Y3/, toBot.ceil.to_s)
  end

  # If a node element text is wider than the sum of it's
  #   child elements, then the child elements need to
  #   be resized to even out the space. This function
  #   recurses down the a child tree and sizes the
  #   children appropriately.
  def fix_child_size(id, current, target)
    children = @e_list.get_children(id)
    @e_list.set_element_width(id, target)

    if(children.length > 0 ) 
      delta = target - current
      target_delta = delta / children.length 

      children.each do |child|
        child_width = @e_list.get_element_width(child)
        fix_child_size(child, child_width, child_width + target_delta)
      end
    end
  end

  # Calculate the width of the element. If the element is
  #   a node, the calculation will be performed recursively
  #   for all child elements.
  def calc_element_width(e)
    w = 0
        
    children = @e_list.get_children(e.id)

    if(children.length == 0)
      w = img_get_txt_width2(e.content, @fontstyle, @font_size) + @font_size
    else
      children.each do |child|
        child_e = @e_list.get_id(child)
        w += calc_element_width(child_e)
      end

      tw = img_get_txt_width2(e.content, @fontstyle, @font_size) + @font_size
      if(tw > w)
        fix_child_size(e.id, w, tw)
        w = tw
      end
    end

    @e_list.set_element_width(e.id, w)
    return w
  end

  # Calculate the width of all elements in a certain level
  def calc_level_width(level)
    w = 0
    e = @e_list.get_first
    while e
      if(e.level == level)
        w += calc_element_width(e)
      end
        e = @e_list.get_next
    end

    return w
  end

  def calc_children_width(id)
    left = 0
    right = 0
    c_list = @e_list.get_children(id)
    return nil if c_list.empty?
    
    c_list.each do |c|
      left =  c.indent if indent == 0 or left > c.indent
    end
    c_list.each do |c|
      right = c.indent + e.width if c.indent + c.width > right
    end
    return [left, right]
  end

  def get_children_indent(id)
    calc_children_width(id)[0]
  end
  
  def get_children_width(id)
    calc_children_width(id)[1] - get_children_indent(id)
  end

  # Parse the elements in the list top to bottom and
  #   draw the elements into the image.
  #   As we it iterate through the levels, the element
  #   indentation is calculated.
  def parse_list

    # Calc element list recursively....
    e_arr = @e_list.get_elements
     
    h = @e_list.get_level_height

    h.times do |i|
      x = 0
      e_arr.each do |j|

        if (j.level == i)
          cw = @e_list.get_element_width(j.id)
          parent_indent = @e_list.get_indent(j.parent)
                  
          if (x <  parent_indent)
            x = parent_indent
          end
                    
          @e_list.set_indent(j.id, x)
          if !@symmetrize
            draw_element(x, i, cw, j.content, j.type)
            if(j.parent != 0 )
              words = j.content.split(" ")
              unless @leafstyle == "nothing" && ETYPE_LEAF == j.type
                if (@leafstyle == "triangle" && ETYPE_LEAF == j.type && x == parent_indent && words.length > 0)
                  txt_width = img_get_txt_width2(j.content, @fontstyle, @font_size)
                  triangle_to_parent(x, i, cw, @e_list.get_element_width(j.parent), txt_width)
                elsif (@leafstyle == "auto" && ETYPE_LEAF == j.type && x == parent_indent)
                  if words.length > 1 || j.triangle
                    txt_width = img_get_txt_width2(j.content, @fontstyle, @font_size)
                    triangle_to_parent(x, i, cw, @e_list.get_element_width(j.parent), txt_width, @symmetrize)
                  else
                    line_to_parent(x, i, cw, @e_list.get_indent(j.parent), @e_list.get_element_width(j.parent))
                  end
                else
                  line_to_parent(x, i, cw, @e_list.get_indent(j.parent), @e_list.get_element_width(j.parent))
                end
              end
            end
          end          
          x += cw
        end
      end
    end
    return true if !@symmetrize
    h.times do |i|
      curlevel = h - i - 1
      indent = 0
      e_arr.each_with_index do |j, idx|
        if (j.level == curlevel)
          # Draw a line to the parent element
          children = @e_list.get_children(j.id)

          tw = img_get_txt_width2(j.content, @fontstyle, @font_size)
          if children.length > 1
            left, right = -1, -1
            children.each do |child|          
              k = @e_list.get_id(child)
              kw = img_get_txt_width2(k.content, @fontstyle, @font_size)              
              left = k.indent + kw / 2 if k.indent + kw / 2 < left or left == -1
              right = k.indent + kw / 2 if k.indent + kw / 2 > right
            end
            draw_element(left, curlevel, right - left, j.content, j.type)
            @e_list.set_indent(j.id, left + (right - left) / 2 -  tw / 2)

            children.each do |child|
              k = @e_list.get_id(child)
              words = k.content.split(" ")
              dw = img_get_txt_width2(k.content, @fontstyle, @font_size)
              unless @leafstyle == "nothing" && ETYPE_LEAF == k.type
                if (@leafstyle == "triangle" && ETYPE_LEAF == k.type && k.indent == j.indent && words.length > 0)
                  txt_width = img_get_txt_width2(k.content, @fontstyle, @font_size)
                  triangle_to_parent(k.indent, curlevel + 1, dw, tw, txt_width)
                elsif (@leafstyle == "auto" && ETYPE_LEAF == k.type && k.indent == j.indent)
                  if words.length > 1 || k.triangle
                    txt_width = img_get_txt_width2(k.content, @fontstyle, @font_size)
                    triangle_to_parent(k.indent, curlevel + 1, dw, tw, txt_width)
                  else
                    line_to_parent(k.indent, curlevel + 1, dw, j.indent, tw)
                  end
                else
                  line_to_parent(k.indent, curlevel + 1, dw, j.indent, tw)
                end
              end
            end
            
          else
            unless children.empty?
              k = @e_list.get_id(children[0])
              kw = img_get_txt_width2(k.content, @fontstyle, @font_size)              
              left = k.indent
              right = k.indent + kw
              draw_element(left, curlevel, right - left, j.content, j.type)
              @e_list.set_indent(j.id, left + (right - left) / 2 -  tw / 2)
            else
             parent = @e_list.get_id(j.parent)
             pw = img_get_txt_width2(parent.content, @fontstyle, @font_size)
             pleft = parent.indent
             pright = pleft + pw
             left = j.indent
             right = left + tw
             if pw > tw
               left = pleft
               right = pright
             end
             draw_element(left, curlevel, right - left, j.content, j.type) 
             @e_list.set_indent(j.id, left + (right - left) / 2 -  tw / 2)             
            end

            unless children.empty?
              k = @e_list.get_id(children[0])
              words = k.content.split(" ")
              dw = img_get_txt_width2(k.content, @fontstyle, @font_size)
              unless @leafstyle == "nothing" && ETYPE_LEAF == k.type              
                if (@leafstyle == "triangle" && ETYPE_LEAF == k.type && words.length > 0)
                  txt_width = img_get_txt_width2(k.content, @fontstyle, @font_size)
                  triangle_to_parent(k.indent, curlevel + 1, dw, 
                                     @e_list.get_element_width(k.parent), txt_width)
                elsif (@leafstyle == "auto" && ETYPE_LEAF == k.type)
                  if words.length > 1 || k.triangle
                    txt_width = img_get_txt_width2(k.content, @fontstyle, @font_size)
                    triangle_to_parent(k.indent, curlevel + 1, dw, tw, txt_width)
                  else
                    line_to_parent(k.indent, curlevel + 1, dw, j.indent, tw)
                  end
                else
                  line_to_parent(k.indent, curlevel + 1, dw, j.indent, tw)
                end
              end
            end
          end
        end
      end
    end
  end

  # Calculate top position from row (level)
  def row2px(row)
   @m[:b_topbot] + @e_height * row + (@m[:v_space] + @font_size) * row
  end
end
