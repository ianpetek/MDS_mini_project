define_system

%% 1. Elipse

h = 0.145;
k = 0.145;                  
a = 0.10;                   
b = 0.05;                   
t = linspace(0, 2*pi, 1000)';
 
x_ref = h + a*cos(t);
y_ref = k + b*sin(t);

x_d = -a * sin(t);
x_dd = -a * cos(t);
x_ddd = a * sin(t);

y_d = b * cos(t);
y_dd = -b * sin(t);
y_ddd = -b*cos(t);

[U_L, U_R, ~, ~, x0] = trajectory_input(x_ref, x_d, x_dd, x_ddd, y_ref, y_d, y_dd, y_ddd);

u = [U_L(:) U_R(:)];

sys = perturbed_system(0);
[y, tSim, x] = lsim(sys, u, t, x0);

xSim = x(:, 1:2);
figure;
plot(x_ref, y_ref, 'r--', xSim(:, 1), xSim(:, 2), 'b-', 'LineWidth', 1.5);
axis equal; axis padded; grid on;
legend('Reference ellipse', 'Simulated trajectory');
paperStyle(gcf, 8.85);
exportgraphics(gcf,'elipse_simulated.pdf','ContentType','vector');

figure
plot(t, U_L, 'b-', t, U_R, 'r-', 'LineWidth', 1.2);
grid on;
xlabel('t [s]'); ylabel('u [V]');
legend('u_{m,L}', 'u_{m,R}');
title('Motor inputs');
paperStyle(gcf, 8.85);
exportgraphics(gcf,'elipse_input.pdf','ContentType','vector');

figure

clear

%% 2. arbitrary spline

mask = imread("tudelft.png", "png", "BackgroundColor",[1,1,1]);
% to black and white
mask = rgb2gray(mask)<255;
[B, ~] = bwboundaries(mask);
% 
% imshow(mask);
% hold on;
% for i = 1:numel(B)
%     boundary = B{i};
%     plot(boundary(:, 2), boundary(:, 1), 'r', 'LineWidth', 1.5);
% end
% hold off;

numPoints = 120;   
all_ctrl = [];               

for i = 1:numel(B)
    curr = B{i};
    
    x = curr(:, 2)';
    y = -curr(:, 1)';
    
    idx = unique(round(linspace(1, length(x), numPoints)));
    controlPoints = [x(idx); y(idx)];
    
    all_ctrl = [all_ctrl controlPoints];
    

end


all_ctrl(:, end+1) = all_ctrl(:, 1);

print_area = 0.29;
draw_size  = 0.20;
margin     = (print_area - draw_size) / 2;
px_to_m    = draw_size / max(size(mask));

all_ctrl = all_ctrl - min(all_ctrl, [], 2);
all_ctrl = margin + px_to_m * all_ctrl;

sp = cscvn(all_ctrl);

% figure('Color', 'white');
% hold on;
% grid on;
% axis equal;
% title('All Drawing Contours as Independent Splines');
% xlabel('X (pixels)');
% ylabel('Y (pixels)');
% fnplt(sp, 2);
% plot(all_ctrl(1, :), all_ctrl(2, :));
% hold off;

v_avg   = 0.05;
s_int   = fnbrk(sp, 'interval');
T       = sum(vecnorm(diff(all_ctrl, 1, 2))) / v_avg;
c       = diff(s_int) / T;  

numEval = 20 * size(all_ctrl, 2);

pos = get_points_from_spline(sp, numEval);
pos_d = get_points_from_spline(fnder(sp, 1), numEval)* c;
pos_dd = get_points_from_spline(fnder(sp, 2), numEval)* c^2;
pos_ddd = get_points_from_spline(fnder(sp, 3), numEval) * c^3;

x = pos(1, :);
y = pos(2, :);
x_d = pos_d(1, :);
y_d = pos_d(2, :);
x_dd = pos_dd(1, :);
y_dd = pos_dd(2, :);
x_ddd = pos_ddd(1, :);
y_ddd = pos_ddd(2, :);
t = linspace(0, T, numEval);

[U_L, U_R, ~, ~, x0] = trajectory_input(x, x_d, x_dd, x_ddd, y, y_d, y_dd, y_ddd);

u = [U_L(:) U_R(:)];

sys = perturbed_system(5);
[y_out, tSim, x_out] = lsim(sys, u, t, x0);


figure;
plot(x, y, 'r--', x_out(:, 1), x_out(:, 2), 'b-', 'LineWidth', 1.5);
axis equal; grid on;axis padded;
xlabel('x [m]'); ylabel('y [m]');
legend('Reference', 'Simulated trajectory');
title('Trajectory');
paperStyle(gcf, 8.85);
exportgraphics(gcf,'tu_delft_draw.pdf','ContentType','vector');

figure;
plot(t, U_L, 'b-', t, U_R, 'r-', 'LineWidth', 1.2);
grid on; 
xlabel('t [s]'); ylabel('u [V]');
legend('u_{m,L}', 'u_{m,R}');
title('Motor inputs');
paperStyle(gcf, 8.85);
exportgraphics(gcf,'tu_delft_input.pdf','ContentType','vector');


%% local funcs
function [U_L, U_R, U_mx, U_my, x0] = trajectory_input(x, x_d, x_dd, x_ddd, y, y_d, y_dd, y_ddd)
    define_system;
    
    %% decoupled currents
    i_x = (m_eq*r_m/K_m)*x_dd + (b_x*r_m/K_m)*x_d;
    i_y = (m_eq*r_m/K_m)*y_dd + (b_y*r_m/K_m)*y_d;
    
    %% current derivatives
    di_x = (m_eq*r_m/K_m)*x_ddd + (b_x*r_m/K_m)*x_dd;
    di_y = (m_eq*r_m/K_m)*y_ddd + (b_y*r_m/K_m)*y_dd;
    
    %% decoupled voltages
    U_mx = L_m*di_x + R_m*i_x + (2*K_m/r_m)*x_d;
    U_my = L_m*di_y + R_m*i_y + (2*K_m/r_m)*y_d;
    
    %% motor voltages
    U_L = 0.5*(U_mx + U_my);
    U_R = 0.5*(U_mx - U_my);
    
    %% initial state [x; y; xdot; ydot; i_L; i_R]
    x0 = [x(1); y(1); x_d(1); y_d(1); 0.5*(i_x(1) + i_y(1)); 0.5*(i_x(1) - i_y(1))];
end

function [points] = get_points_from_spline(sp, numPoints)
    interval = fnbrk(sp, 'interval'); 
    t_start = interval(1);
    t_end = interval(2);
    
    t_eval = linspace(t_start, t_end, numPoints);
    
    points = fnval(sp, t_eval);
end