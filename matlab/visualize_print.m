%% plot_from_simout.m
% Plot the printer output from out.simout after pressing Run in Simulink.
% Expects the To Workspace block (Save format: Timeseries) to receive the
% Mux signal [pos_x; pos_y; extruding].

try
    ts = out.simout;
catch
    error(['No out.simout found. Run the model first, and check that the ', ...
           'single simulation output name is "out".']);
end

% Get time and data (handles Timeseries and Structure-with-time formats)
if isa(ts, 'timeseries')
    t = ts.Time;  D = ts.Data;
else
    t = ts.time;  D = ts.signals.values;
end
D = squeeze(D);
if size(D, 1) ~= numel(t), D = D.'; end    % make it N x 3

px  = D(:, 1);
py  = D(:, 2);
ext = D(:, 3) > 0.5;

% Masks: keep one sample of overlap at each switch so the lines connect
on  = ext  | [false; ext(1:end-1)];
off = ~ext | [false; ~ext(1:end-1)];

pr_x = px;  pr_x(~on)  = NaN;   pr_y = py;  pr_y(~on)  = NaN;
tr_x = px;  tr_x(~off) = NaN;   tr_y = py;  tr_y(~off) = NaN;

figure('Name', 'Printer output'); hold on; grid on; axis equal
plot(tr_x, tr_y, '--', 'Color', [0.6 0.6 0.6], 'LineWidth', 1);
plot(pr_x, pr_y, '-',  'Color', [0.85 0.2 0.1], 'LineWidth', 2.5);
plot(px(1), py(1), 'ko', 'MarkerFaceColor', 'k');
xlabel('x [m]');  ylabel('y [m]');
legend('travel', 'printed', 'start', 'Location', 'best');
title(sprintf('Printer output (t = %.1f s)', t(end)));