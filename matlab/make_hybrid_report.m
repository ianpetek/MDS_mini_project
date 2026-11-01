%% make_report_figures.m
% Q3.1 report figures for ONE workflow:
%   1. the printer starts printing the path,
%   2. the filament runs out part way  -> automatic filament change,
%   3. printing resumes, but the user does not like the new colour,
%   4. the user presses C               -> second filament change,
%   5. printing resumes and the print completes.
%
% The script finds the right moments by itself:
%   - probe run 1 (no events) measures the whole print,
%   - the spool is set so it runs out at RUNOUT_FRAC of the print,
%   - probe run 2 (run-out only) finds when printing resumes and ends,
%   - C is pressed at C_FRAC of the way between resume and the end,
%   - the final run has both events, and all figures come from it.
%
% Every plot is its own file (PDF, PNG, .fig). All time plots have the same
% width, time axis and axes position, so they line up when stacked.
% data.mat holds all time series for re-plotting.
%
% Needs in the model:
%   - logged signals: x, y, T_n (Bus Selector <x>, <y>, <T_n> is fine),
%     is_extruding, total_amount_extruded
%   - each machine's state as a logged "Create output for monitoring" output
%   - the chart compares total_amount_extruded with p.(FIL_FIELD)

params;                                           % p, PlantState, defaults
model   = 'hybrid_system';
outroot = '/home/hk/MDS_mini_project/report/figures/q31/final_test';   % change if needed

%% Settings
T_END       = 400;        % stop time [s]; raise it if the print does not finish
FIL_FIELD   = 'fil_max';  % field of p holding the spool length [m]
RUNOUT_FRAC = 0.55;       % spool runs out after this fraction of the print
                          % (keep > 0.5, so the refilled spool lasts to the end)
C_FRAC      = 0.5;        % C is pressed this far between resume and print end
T_HI  = 350;              % nozzle "hot" threshold in the chart [K]
T_LO  = 350;              % nozzle "cold" threshold in the chart [K]
T_MAX = 370;              % "too hot" threshold [K]

% Layout in centimetres (same for every time plot, so they stack exactly)
opts.FIG_W    = 15;       % figure width = your LaTeX \textwidth [cm]
opts.LEFT     = 3.8;
opts.RIGHT    = 0.5;
opts.BOTTOM   = 1.1;
opts.TOP      = 0.3;
opts.H_MODE   = 3.0;
opts.H_SIGNAL = 4.5;
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

if ~exist(outroot, 'dir'), mkdir(outroot); end
load_system(model);
p0 = p;
if ~isfield(p0, FIL_FIELD)
    error('p.%s does not exist. Set FIL_FIELD to the spool-length field your chart uses.', FIL_FIELD);
end

%% Probe run 1: whole print, no events
fprintf('Probe run 1 (no events) ...\n');
pn = p0;  pn.(FIL_FIELD) = 1e6;
outN = run_sim(model, T_END, pn, []);
[~, L] = getsig(outN, 'total_amount_extruded');
L_total = L(end);
fprintf('  whole print extrudes %.3f m\n', L_total);

%% Probe run 2: filament runs out, no C
pf = p0;  pf.(FIL_FIELD) = RUNOUT_FRAC * L_total;
fprintf('Probe run 2 (run-out at %.0f %% of the print) ...\n', 100 * RUNOUT_FRAC);
dF = collect(run_sim(model, T_END, pf, []));
t_F      = first_change(dF.filament.t, dF.filament.mode);
t_resume = back_to_start(dF.filament.t, dF.filament.mode);
t_done   = time_of(dF.printer, 'COMPLETED');
if any(isnan([t_F t_resume t_done]))
    error(['Probe run 2 did not show run-out -> change -> resume -> complete ' ...
           '(t_F=%.1f, t_resume=%.1f, t_done=%.1f). Raise T_END or check RUNOUT_FRAC.'], ...
           t_F, t_resume, t_done);
end
t_C = t_resume + C_FRAC * (t_done - t_resume);
fprintf('  run-out at %.1f s, printing resumes at %.1f s, ends at %.1f s\n', t_F, t_resume, t_done);
fprintf('  -> C will be pressed at %.1f s\n', t_C);

%% Final run: run-out, then C
fprintf('Final run ...\n');
d = collect(run_sim(model, T_END, pf, t_C));
t_F_final = first_change(d.filament.t, d.filament.mode);
if isnan(time_of(d.printer, 'COMPLETED'))
    warning('The print did not complete within T_END = %g s. Raise T_END.', T_END);
end

evts(1).t = t_F_final;  evts(1).label = 'filament out';
evts(2).t = t_C;        evts(2).label = '$C$';

make_figures(d, pf, FIL_FIELD, outroot, evts, opts);
save(fullfile(outroot, 'data.mat'), 'd', 'evts', 'opts');
write_events(d, outroot);

%% Chart and model images
try
    print(['-s' model], '-dpdf', fullfile(outroot, 'hybrid_model_overview.pdf'));
catch err
    warning('Could not export the model diagram: %s', err.message);
end

reset(groot);
fprintf('Done. Figures are in %s\n', outroot);


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
    % First mode change after the start (NaN if none).
    [tc, ~] = changes(tm, md);
    if numel(tc) >= 2, t = tc(2); else, t = NaN; end
end

function t = back_to_start(tm, md)
    % First time the mode returns to its initial value after having left it.
    [tc, vc] = changes(tm, md);
    t = NaN;
    for k = 3:numel(vc)
        if vc(k) == vc(1), t = tc(k); return; end
    end
end

function t = time_of(m, name)
    % First time a machine enters the state called name (NaN if never).
    idx = find(contains(string(m.mode), name), 1);
    if isempty(idx), t = NaN; else, t = m.t(idx); end
end

function write_events(d, folder)
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
function make_figures(d, p, FIL_FIELD, folder, evts, o)
    evtcol = [0.55 0.15 0.65];

    % 1. Head path: one colour per spool
    f = figure('Units', 'centimeters', 'Position', [2 2 0.6*o.FIG_W 0.6*o.FIG_W], 'Color', 'w');
    light(f);
    ax = axes(f); hold(ax, 'on'); axis(ax, 'equal');
    edges_t = [-inf, evts(1).t, evts(2).t, inf];
    cols  = {[0.80 0.15 0.15], [0.95 0.55 0.10], [0.10 0.60 0.20]};
    names = {'first spool', 'refill (unwanted colour)', 'after colour change'};
    plot(ax, d.x, d.y, ':', 'Color', [0.55 0.55 0.55], 'DisplayName', 'travel');
    for i = 1:3
        seg = d.t >= edges_t(i) & d.t < edges_t(i+1);
        plot(ax, masked(d.x, d.ext & seg), masked(d.y, d.ext & seg), '-', ...
            'Color', cols{i}, 'LineWidth', 1.5, 'DisplayName', names{i});
    end
    plot(ax, p.wipe_x, p.wipe_y, 'ks', 'MarkerFaceColor', 'k', 'MarkerSize', 5, 'DisplayName', 'wipe location');
    if isfield(p, 'path')
        plot(ax, p.path(:,1), p.path(:,2), 'o', 'Color', [0.2 0.3 0.8], 'MarkerSize', 3, 'DisplayName', 'path points');
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
    event_lines(ax, evts, evtcol);
    ylabel(ax, '$T_n$ [K]');
    save_fig(f, folder, '2_nozzle_temperature');

    % 3-5. Mode staircases
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
        event_lines(ax, evts, evtcol);
        ylabel(ax, plots{k, 3}, 'Interpreter', 'none');
        save_fig(f, folder, plots{k, 2});
    end

    % 6. Filament extruded on the current spool, extruding periods shaded
    [f, ax] = timefig(o, o.H_SIGNAL);
    spool = p.(FIL_FIELD);
    ytop = max(max(d.L), spool) * 1.15;
    if ytop <= 0, ytop = 1; end
    [s, e] = runs(d.ext);
    for i = 1:numel(s)
        patch(ax, d.t([s(i) e(i) e(i) s(i)]), [0 0 ytop ytop], [0.10 0.60 0.20], ...
            'FaceAlpha', 0.10, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    end
    plot(ax, d.tL, d.L, 'k-', 'LineWidth', 1.2, 'DisplayName', '$L$ (on current spool)');
    yline(ax, spool, '--', '$L_{spool}$', 'Color', [0.80 0.15 0.15], 'Interpreter', 'latex', ...
        'LabelHorizontalAlignment', 'left', 'HandleVisibility', 'off');
    patch(ax, NaN, NaN, [0.10 0.60 0.20], 'FaceAlpha', 0.10, 'EdgeColor', 'none', ...
        'DisplayName', 'extruding');
    event_lines(ax, evts, evtcol);
    ylim(ax, [0 ytop]);
    ylabel(ax, '$L$ [m]');
    legend(ax, 'Location', 'northwest', 'Box', 'off');
    save_fig(f, folder, '6_filament_extruded');
end

function [f, ax] = timefig(o, h)
    f = figure('Units', 'centimeters', 'Position', [2 2 o.FIG_W h], 'Color', 'w');
    light(f);
    ax = axes(f, 'Units', 'centimeters', ...
        'Position', [o.LEFT, o.BOTTOM, o.FIG_W - o.LEFT - o.RIGHT, h - o.BOTTOM - o.TOP]);
    hold(ax, 'on');
    xlim(ax, [0 o.T_END]);
    xlabel(ax, 'time [s]');
end

function event_lines(ax, evts, col)
    for i = 1:numel(evts)
        if ~isnan(evts(i).t)
            xline(ax, evts(i).t, '-', evts(i).label, 'Color', col, 'Interpreter', 'latex', ...
                'LabelVerticalAlignment', 'top', 'HandleVisibility', 'off');
        end
    end
end

function light(f)
    try
        theme(f, 'light');
    catch
    end
end

function save_fig(f, folder, name)
    pos = get(f, 'Position');
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
    s = out.logsout.get(name);
    if isempty(s)
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
               'General -> tick "Create output for monitoring", wire the new port to a ' ...
               'Terminator and right-click the wire -> Log Selected Signals.'], machine);
    end
    if isnumeric(d) && all(ismember(unique(double(d)), [0 1]))
        error('%s is only logged as self activity (0/1). Use "Create output for monitoring".', machine);
    end
end

function [num, vals, labs] = modeinfo(md)
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
    if iscell(v) || ischar(v) || isstring(v)
        v = categorical(cellstr(string(v)));
    end
    idx = [1; find(v(2:end) ~= v(1:end-1)) + 1];
    tc = t(idx);
    vc = v(idx);
end

function [s, e] = runs(mask)
    m = [false; mask(:); false];
    s = find(diff(m) == 1);
    e = find(diff(m) == -1) - 1;
end