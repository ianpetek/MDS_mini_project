function paperStyle(fig, widthCm, aspect, fontSize)
% PAPERSTYLE  Style a figure so it matches a LaTeX paper.
%   Call this after plotting, right before exporting.
%
%   paperStyle(gcf, 8.85)           % IEEE single column, golden ratio
%   paperStyle(gcf, 18.1, 0.35)     % IEEE double column, wide and short
%   paperStyle(gcf, 15.9, 0.5, 9)   % A4 article textwidth, 9 pt text
%
%   Export at natural size so the fonts are not rescaled:
%   exportgraphics(gcf, 'fig.pdf', 'ContentType', 'vector')
%   and in LaTeX: \includegraphics{fig.pdf}   (no width= option)
arguments
    fig = gcf
    widthCm  (1,1) double = 8.85   % get yours with \the\columnwidth (pt / 28.45 = cm)
    aspect   (1,1) double = 0.618  % height / width
    fontSize (1,1) double = 8      % ~ \footnotesize / caption size of a 10 pt doc
end

% Physical size = size in the paper
fig.Units = 'centimeters';
fig.Position(3:4) = [widthCm, widthCm * aspect];
fig.Color = 'w';

% Computer Modern text everywhere, one font size
set(findall(fig, '-property', 'Interpreter'), 'Interpreter', 'latex');
set(findall(fig, '-property', 'TickLabelInterpreter'), 'TickLabelInterpreter', 'latex');
set(findall(fig, '-property', 'FontSize'), 'FontSize', fontSize);

% Thin black axes, light grid, ticks inside (classic LaTeX/pgfplots look)
for ax = findall(fig, 'Type', 'axes')'
    set(ax, 'LineWidth', 0.5, 'Box', 'on', 'Layer', 'top', ...
        'TickDir', 'in', 'TickLength', [0.015 0.015], ...
        'XGrid', 'on', 'YGrid', 'on', 'GridAlpha', 0.12, ...
        'XColor', 'k', 'YColor', 'k', ...
        'LabelFontSizeMultiplier', 1, 'TitleFontSizeMultiplier', 1);
end

% Data lines a bit heavier than the axes; frameless legends
set(findall(fig, 'Type', 'line'), 'LineWidth', 1.0);
set(findall(fig, 'Type', 'legend'), 'Box', 'off');
end