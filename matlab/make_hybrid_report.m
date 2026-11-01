%% make_report_figures.m
% Q3.1 report figures for two scenarios, each in its own folder:
%   colour_change    - C is pressed half way through the print
%   filament_runout  - the spool runs out half way through the print
%
% Every plot is saved as its own file (PDF for LaTeX, PNG preview, and an
% editable .fig). All time plots have the same width, the same time axis and
% the SAME axes position inside the figure, so they line up exactly when you
% stack them later (in LaTeX with subfigure/stacked \includegraphics, or in
% MATLAB by copying axes out of the .fig files). Each folder also gets a
% data.mat with all the time series, so you can re-plot without re-running.
%
% Run from the matlab/ folder:   >> make_report_figures
%
% Needs in the model:
%   - logged signals: x, y, T_n (Bus Selector <x>, <y>, <T_n> is fine),
%     is_extruding, total_amount_extruded
%   - each machine's state as a "Create output for monitoring" output that is
%     logged (PrinterMachine: Leaf state activity, the others: Child activity)
%   - the chart compares total_amount_extruded with p.(FIL_FIELD)

params;                                           % p, PlantState, defaults
model   = 'hybrid_system';
outroot = fullfile('..', 'report', 'figures', 'q31');    % change if needed

%% Settings
T_END     = 200;          % stop time [s]
FIL_FIELD = 'fil_max';    % field of p holding the spool length [m]
T_HI  = 350;              % nozzle "hot" threshold in the chart [K]
T_LO  = 350;              % nozzle "cold" threshold in the chart [K]
T_MAX = 370;              % "too hot" threshold [K]

% Layout in centimetres. Every time plot uses the same LEFT/RIGHT margins, so
% the time axes line up when stacked. LEFT leaves room for state names.
opts.FIG_W    = 15;       % figure width = your LaTeX \textwidth [cm]
opts.LEFT     = 3.8;
opts.RIGHT    = 0.5;
opts.BOTTOM   = 1.1;
opts.TOP      = 0.3;
opts.H_MODE   = 3.0;      % height of a mode (staircase) plot
opts.H_SIGNAL = 4.5;      % height of a signal plot (temperature, extrusion)
opts.FONT     = 9;
opts.T_END    = T_END;
opts.T_HI = T_HI; opts.T_LO = T_LO; opts.T_MAX = T_MAX;

set(groot, ...
    'defaultFigureColor',              'w', ...
    'defaultAxesColor',                'w', ...
    'defaultAxesFontName',             'Times', ...
    'defaultTextFontName',             'Times', ...
    'defaultAxesFontSize',             opts.FONT, ...
    'defaultTextFontSize',             opts.FONT, ...
    'defaultLegendFontSize',           opts.FONT - 1, ...
    'defaultAxesTickLabelInterpreter', 'latex', ...
    'defaultTextInterpreter',          'latex', ...
    'defaultLegendInterpreter',        'latex', ...
    'defaultAxesBox',                  'on', ...
    'defaultAxesXGrid',                'on', ...
    'defaultAxesYGrid',                'on', ...
    'defaultAxesGridAlpha',            0.15, ...
    'defaultAxesLineWidth',            0.5, ...
    'defaultLineLineWidth',            1.0);

load_system(model);
p0 = p;
if ~isfield(p0, FIL_FIELD)
    error('p.%s does not exist. Set FIL_FIELD to the spool-length field your chart uses.', FIL_FIELD);
end

%% Probe run: full print, no events, to find "half way"
fprintf('Probe run (no events) ...\n');
pn = p0;  pn.(FIL_FIELD) = 1e6;                   % spool never runs out
outN = run_sim(model, T_END, pn, []);
[tL, L] = getsig(outN, 'total_amount_extruded');
L_total = L(end);
t_mid   = tL(find(L >= L_total / 2, 1));
fprintf('Full print extrudes %.3f m; half way at t = %.1f s\n\n', L_total, t_mid);

%% The two scenarios
cases(1).name    = 'case1_colour_change';
cases(1).t_C     = t_mid;                        % press C half way
cases(1).fil_max = 1e6;                          % spool never runs out
cases(1).label   = '$C$';

cases(2).name    = 'case2_filament_runout';
cases(2).t_C     = [];                           % never press C
cases(2).fil_max = L_total / 2;                  % spool runs out half way
cases(2).label   = 'filament out';

for c = 1:numel(cases)
    cs = cases(c);
    folder = fullfile(outroot, cs.name);
    if ~exist(folder, 'dir'), mkdir(folder); end
    fprintf('=== %s ===\n', cs.name);

    pc = p0;  pc.(FIL_FIELD) = cs.fil_max;
    out = run_sim(model, T_END, pc, cs.t_C);
    d   = collect(out);

    % Event time: the C press, or the moment the filament machine first moves
    if ~isempty(cs.t_C)
        t_evt = cs.t_C;
    else
        t_evt = first_change(d.filament.t, d.filament.mode);
    end

    make_case_figures(d, pc, FIL_FIELD, folder, cs.label, t_evt, opts);
    save(fullfile(folder, 'data.mat'), 'd', 't_evt', 'cs', 'opts');
    write_events(d, folder);
    fprintf('Saved in %s\n\n', folder);
end

%% Chart and model images (once)
try
    print(['-s' model], '-dpdf', fullfile(outroot, 'hybrid_model_overview.pdf'));
catch err
    warning('Could not export the model diagram: %s', err.message);
end
try
    sfprint([model '/Chart'], 'png', fullfile(outroot, 'stateflow_chart.png'), 1);
catch err
    warning('Could not export the chart (take a screenshot instead): %s', err.message);
end

reset(groot);
fprintf('Done. All figures are under %s\n', outroot);


%% ====================================================================
%% Simulation and data
%% ====================================================================
function out = run_sim(model, T_END, pcase, t_C)
    % One run with its own p and C presses, without changing the model.
    C = [0 0];
    if ~isempty(t_C), C = [0 0; t_C 1; t_C + 1 0]; end
    simIn = Simulink.SimulationInput(model);
    simIn = simIn.setModelParameter('StopTime', num2str(T_END), 'EnablePacing', 'off');
    simIn = simIn.setVariable('p', pcase);
    simIn = simIn.setVariable('C_pressed', C);
    simIn = simIn.setVariable('F_pressed', [0 0]);
    out = sim(simIn);
end

function d = collect(out)
    % All signals the figures need, as plain vectors.
    [d.t, d.x] = getsig(out, 'x');
    [ty, y]    = getsig(out, 'y');
    d.y        = interp1(ty, y, d.t, 'previous', 'extrap');
    [d.tT, d.Tn] = getsig(out, 'T_n');
    [te, e]    = getsig(out, 'is_extruding');
    d.ext      = interp1(te, double(e), d.t, 'previous', 'extrap') > 0.5;
    [d.tL, d.L] = getsig(out, 'total_amount_extruded');
    [d.printer.t,  d.printer.mode]  = getmode(out, 'PrinterMachine');
    [d.filament.t, d.filament.mode] = getmode(out, 'FilamentMachine');
    [d.nozzle.t,   d.nozzle.mode]   = getmode(out, 'NozzleMachine');
end

function t = first_change(tm, md)
    % Time of the first mode change after the start (NaN if none).
    [tc, ~] = changes(tm, md);
    if numel(tc) >= 2, t = tc(2); else, t = NaN; end
end

function write_events(d, folder)
    % Every mode change of the three machines, in time order, to events.csv.
    m = {d.printer, d.filament, d.nozzle};
    names = {'printer', 'filament', 'nozzle'};
    rows = {};
    for k = 1:3
        [tc, mc] = changes(m{k}.t, m{k}.mode);
        for i = 1:numel(tc)
            rows(end+1, :) = {tc(i), names{k}, char(string(mc(i)))}; %#ok<AGROW>
        end
    end
    [~, order] = sort(cell2mat(rows(:, 1)));
    rows = rows(order, :);
    for i = 1:size(rows, 1)
        fprintf('%8.1f  %-9s  %s\n', rows{i, :});
    end
    writecell([{'time_s', 'machine', 'mode'}; rows], fullfile(folder, 'events.csv'));
end


%% ====================================================================
%% Figures (one file each)
%% ====================================================================
function make_case_figures(d, p, FIL_FIELD, folder, label, t_evt, o)
    evtcol = [0.55 0.15 0.65];

    % 1. Head path
    f = figure('Units', 'centimeters', 'Position', [2 2 0.6*o.FIG_W 0.6*o.FIG_W], 'Color', 'w');
    light(f);
    ax = axes(f); hold(ax, 'on'); axis(ax, 'equal');
    before = d.t <  t_evt;
    after  = d.t >= t_evt;
    if isnan(t_evt), before = true(size(d.t)); after = false(size(d.t)); end
    plot(ax, d.x, d.y, ':', 'Color', [0.55 0.55 0.55], 'DisplayName', 'travel');
    plot(ax, masked(d.x, d.ext & before), masked(d.y, d.ext & before), '-', ...
        'Color', [0.80 0.15 0.15], 'LineWidth', 1.5, 'DisplayName', 'printed before change');
    plot(ax, masked(d.x, d.ext & after),  masked(d.y, d.ext & after),  '-', ...
        'Color', [0.10 0.60 0.20], 'LineWidth', 1.5, 'DisplayName', 'printed after change');
    plot(ax, p.wipe_x, p.wipe_y, 'ks', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'DisplayName', 'wipe location');
    if isfield(p, 'path')
        plot(ax, p.path(:,1), p.path(:,2), 'o', 'Color', [0.2 0.3 0.8], 'MarkerSize', 4, 'DisplayName', 'path points');
    end
    xlabel(ax, '$x$ [m]'); ylabel(ax, '$y$ [m]');
    legend(ax, 'Location', 'southoutside', 'NumColumns', 2, 'Box', 'off');
    save_fig(f, folder, '1_head_path');

    % 2. Nozzle temperature
    [f, ax] = timefig(o, o.H_SIGNAL);
    plot(ax, d.tT, d.Tn, '-', 'Color', [0.15 0.30 0.75], 'LineWidth', 1.2, 'DisplayName', '$T_n$');
    yline(ax, o.T_HI, '--', '$T_{hi}$', 'Color', [0.80 0.15 0.15], 'Interpreter', 'latex', ...
        'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
    if o.T_LO ~= o.T_HI
        yline(ax, o.T_LO, '--', '$T_{lo}$', 'Color', [0.10 0.50 0.70], 'Interpreter', 'latex', ...
            'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
    end
    yline(ax, o.T_MAX, ':', '$T_{max}$', 'Color', 'k', 'Interpreter', 'latex', ...
        'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
    event_line(ax, t_evt, label, evtcol);
    ylabel(ax, '$T_n$ [K]');
    save_fig(f, folder, '2_nozzle_temperature');

    % 3-5. Mode staircases (same size, stack directly under the temperature)
    plots = {d.nozzle,   '3_nozzle_mode',   'Nozzle'; ...
             d.printer,  '4_printer_mode',  'Printer'; ...
             d.filament, '5_filament_mode', 'Filament'};
    for k = 1:size(plots, 1)
        m = plots{k, 1};
        [num, vals, labs] = modeinfo(m.mode);
        [f, ax] = timefig(o, max(o.H_MODE, 1.6 + 0.35 * numel(vals)));
        stairs(ax, m.t, num, 'Color', [0.15 0.30 0.75], 'LineWidth', 1.2);
        yticks(ax, vals); yticklabels(ax, strrep(labs, '_', ' '));
        ax.TickLabelInterpreter = 'none';
        ylim(ax, [min(vals) - 0.5, max(vals) + 0.5]);
        event_line(ax, t_evt, label, evtcol);
        ylabel(ax, plots{k, 3}, 'Interpreter', 'none');
        save_fig(f, folder, plots{k, 2});
    end

    % 6. Filament extruded, with the extruding periods shaded
    [f, ax] = timefig(o, o.H_SIGNAL);
    spool = p.(FIL_FIELD);
    show_spool = spool < 1e5;
    ytop = max(d.L) * 1.15;
    if show_spool, ytop = max(ytop, spool * 1.15); end
    if ytop <= 0, ytop = 1; end
    [s, e] = runs(d.ext);
    for i = 1:numel(s)
        patch(ax, d.t([s(i) e(i) e(i) s(i)]), [0 0 ytop ytop], [0.10 0.60 0.20], ...
            'FaceAlpha', 0.10, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    end
    plot(ax, d.tL, d.L, 'k-', 'LineWidth', 1.2, 'DisplayName', '$L$ (extruded)');
    if show_spool
        yline(ax, spool, '--', '$L_{spool}$', 'Color', [0.80 0.15 0.15], 'Interpreter', 'latex', ...
            'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
    end
    patch(ax, NaN, NaN, [0.10 0.60 0.20], 'FaceAlpha', 0.10, 'EdgeColor', 'none', ...
        'DisplayName', 'extruding');                         % legend entry only
    event_line(ax, t_evt, label, evtcol);
    ylim(ax, [0 ytop]);
    ylabel(ax, '$L$ [m]');
    legend(ax, 'Location', 'northwest', 'Box', 'off');
    save_fig(f, folder, '6_filament_extruded');
end

function [f, ax] = timefig(o, h)
    % A figure of fixed size with the axes at a fixed position, so every
    % time plot has its time axis in exactly the same place.
    f = figure('Units', 'centimeters', 'Position', [2 2 o.FIG_W h], 'Color', 'w');
    light(f);
    ax = axes(f, 'Units', 'centimeters', ...
        'Position', [o.LEFT, o.BOTTOM, o.FIG_W - o.LEFT - o.RIGHT, h - o.BOTTOM - o.TOP]);
    hold(ax, 'on');
    xlim(ax, [0 o.T_END]);
    xlabel(ax, 'time [s]');
end

function event_line(ax, t_evt, label, col)
    if ~isnan(t_evt)
        xline(ax, t_evt, '-', label, 'Color', col, 'Interpreter', 'latex', ...
            'LabelVerticalAlignment', 'top', 'HandleVisibility', 'off');
    end
end

function light(f)
    try
        theme(f, 'light');            % newer MATLAB versions may default to dark
    catch
    end
end

function save_fig(f, folder, name)
    % Save WITHOUT cropping, so all files keep their exact layout and stack
    % cleanly: vector PDF, 300 dpi PNG, and an editable .fig.
    pos = get(f, 'Position');                   % centimetres
    set(f, 'PaperUnits', 'centimeters', 'PaperSize', pos(3:4), ...
        'PaperPosition', [0 0 pos(3:4)], 'InvertHardcopy', 'off');
    base = fullfile(folder, name);
    try
        print(f, [base '.pdf'], '-dpdf', '-vector');
    catch
        print(f, [base '.pdf'], '-dpdf', '-painters');
    end
    print(f, [base '.png'], '-dpng', '-r300');
    savefig(f, [base '.fig']);
end


%% ====================================================================
%% Reading logged signals
%% ====================================================================
function [t, d] = getsig(out, name)
    % Time and data of a logged signal, as column vectors.
    s = out.logsout.get(name);
    if isempty(s)
        % Bus Selector outputs only carry a propagated name such as <x>.
        for i = 1:out.logsout.numElements
            e = out.logsout.getElement(i);
            pn = '';
            if isprop(e, 'PropagatedName'), pn = e.PropagatedName; end
            if any(strcmp(name, {e.Name, pn})) || strcmp(['<' name '>'], e.Name)
                s = e;
                break
            end
        end
    end
    if isempty(s)
        error('Signal "%s" is not logged. Type out.logsout.getElementNames to see what is logged.', name);
    end
    if numel(s) > 1
        % Same name twice (e.g. self and child activity): take the one with
        % the most distinct values.
        best = 1; bestn = -1;
        for i = 1:numel(s)
            try
                ni = numel(unique(squeeze(s{i}.Values.Data)));
            catch
                ni = 0;
            end
            if ni > bestn, best = i; bestn = ni; end
        end
        s = s{best};
    end
    v = s.Values;
    t = v.Time(:);
    d = squeeze(v.Data);
    d = d(:);
end

function [t, d] = getmode(out, machine)
    % The logged state of one machine. Prefers the enum from "Create output
    % for monitoring" (its type name starts with the machine's name, e.g.
    % PrinterMachineModeType), whether or not the wire is named.
    for i = 1:out.logsout.numElements
        e = out.logsout.getElement(i);
        v = squeeze(e.Values.Data);
        if (isenum(v) || iscategorical(v)) && startsWith(class(v), machine)
            t = e.Values.Time(:);
            d = v(:);
            return
        end
    end
    try
        [t, d] = getsig(out, machine);
    catch
        error(['No state output found for %s. Select it in the chart -> Properties -> ' ...
               'General -> tick "Create output for monitoring" (Child activity; Leaf state ' ...
               'activity for PrinterMachine), wire the new port to a Terminator and ' ...
               'right-click the wire -> Log Selected Signals.'], machine);
    end
    if isnumeric(d) && all(ismember(unique(double(d)), [0 1]))
        error(['%s is only logged as self activity (0/1). Use "Create output for ' ...
               'monitoring" instead, as described above.'], machine);
    end
end

function [num, vals, labs] = modeinfo(md)
    % Numbers for plotting a mode signal, plus tick labels.
    if isenum(md)
        m    = enumeration(class(md));
        num  = double(md);
        vals = double(m);
        labs = string(m);
    elseif iscategorical(md) || isstring(md) || iscellstr(md) || ischar(md)
        c    = categorical(cellstr(string(md)));
        labs = string(categories(c));
        num  = double(c);
        vals = (1:numel(labs))';
    else
        num  = double(md);
        vals = unique(num);
        labs = string(vals);
    end
    vals = double(vals(:));
    if isempty(vals), vals = 0; labs = "none"; end
end

function v = masked(v, keep)
    v(~keep) = NaN;
end

function [tc, vc] = changes(t, v)
    % Times and values where a mode signal changes, including the first value.
    if iscell(v) || ischar(v) || isstring(v)
        v = categorical(cellstr(string(v)));
    end
    idx = [1; find(v(2:end) ~= v(1:end-1)) + 1];
    tc = t(idx);
    vc = v(idx);
end

function [s, e] = runs(mask)
    % Start and end indices of each run of true values.
    m = [false; mask(:); false];
    s = find(diff(m) == 1);
    e = find(diff(m) == -1) - 1;
end