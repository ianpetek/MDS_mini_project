%% export_chart_figures.m
% Turns the Stateflow chart into report material, read straight from the model.
% For each top-level machine (PrinterMachine, FilamentMachine, NozzleMachine):
%   - ONE state diagram (vector PDF, paper style). Composite states such as
%     IN_PROGRESS are drawn as a rounded box around their own sub-states,
%     inside the same figure, with their initial state and history junction.
%   - a LaTeX table with every transition: from, to, guard, reset
%   - a LaTeX table with each state's entry/during actions
% Commented-out states (Ian's demo MotorsMachine) are left out automatically.
%
% Run from anywhere:   >> export_chart_figures
% Needs Graphviz for the diagrams (Ubuntu: sudo apt install graphviz).

model  = 'hybrid_system';
chartP = [model '/Chart'];
outdir = '/home/hk/MDS_mini_project/report/figures/statechart';   % change if needed

EDGE_LABELS = 'guard';    % 'guard' = guards only (clean); 'full' = guard {reset}
WRAP        = 28;         % wrap edge labels after about this many characters
FONT        = 'Times';
FONT_SIZE   = 11;
RANKDIR     = 'LR';       % 'LR' left-to-right, 'TB' top-to-bottom

if ~exist(outdir, 'dir'), mkdir(outdir); end
load_system(model);
rt = sfroot;
ch = rt.find('-isa', 'Stateflow.Chart', 'Path', chartP);
if isempty(ch), error('Chart %s not found.', chartP); end

allS = ch.find('-isa', 'Stateflow.State');
allT = ch.find('-isa', 'Stateflow.Transition');
allJ = ch.find('-isa', 'Stateflow.Junction');
allS = allS(~arrayfun(@iscommented, allS));
allT = allT(~arrayfun(@iscommented, allT));

if ~has_graphviz()
    error(['Graphviz (dot) not found. Install it with:  sudo apt install graphviz ' ...
           '  then run this script again.']);
end

% Top-level machines: visible states directly under the chart that have children
for M = allS(:)'
    if ~isa(M.getParent, 'Stateflow.Chart') || isempty(direct_children(M, allS))
        continue
    end
    fprintf('Diagram for %s\n', M.Name);
    edges = collect_edges(M, allT);
    inits = collect_inits(M, allT);

    dotf = fullfile(outdir, [M.Name '.dot']);
    write_dot(dotf, M, allS, allJ, edges, inits, EDGE_LABELS, WRAP, FONT, FONT_SIZE, RANKDIR);
    pdff = fullfile(outdir, [M.Name '.pdf']);
    [st, msg] = system(sprintf('LD_LIBRARY_PATH= dot -Tpdf "%s" -o "%s"', dotf, pdff));
    if st ~= 0, warning('dot failed for %s: %s', M.Name, msg); end

    write_transition_table(fullfile(outdir, [M.Name '_transitions.tex']), M.Name, edges);
    write_state_table(fullfile(outdir, [M.Name '_states.tex']), M, allS);
end
fprintf('Done. Files in %s\n', outdir);


%% ====================================================================
%% Reading the chart
%% ====================================================================
function tf = iscommented(o)
    tf = false;
    for prop = {'IsExplicitlyCommented', 'IsImplicitlyCommented'}
        if isprop(o, prop{1}) && o.(prop{1}), tf = true; end
    end
end

function kids = direct_children(s, allS)
    keep = false(size(allS));
    for i = 1:numel(allS)
        par = allS(i).getParent;
        keep(i) = isa(par, 'Stateflow.State') && par.Id == s.Id;
    end
    kids = allS(keep);
end

function tf = inside(o, M)
    % True if object o is (somewhere) inside state M.
    tf = false;
    if isempty(o), return; end
    cur = o;
    while true
        par = cur.getParent;
        if isempty(par) || ~isa(par, 'Stateflow.State'), return; end
        if par.Id == M.Id, tf = true; return; end
        cur = par;
    end
end

function edges = collect_edges(M, allT)
    % Every non-default transition with both ends inside machine M.
    edges = struct('src', {}, 'dst', {}, 'event', {}, 'guard', {}, 'action', {});
    for t = allT(:)'
        src = t.Source;  dst = t.Destination;
        if isempty(src) || isempty(dst), continue; end
        if ~(inside(src, M) && inside(dst, M)), continue; end
        if ~isa(src, 'Stateflow.State'), continue; end
        [ev, gd, ac] = parse_label(t.LabelString);
        edges(end+1) = struct('src', src, 'dst', dst, 'event', ev, 'guard', gd, 'action', ac); %#ok<AGROW>
    end
end

function inits = collect_inits(M, allT)
    % Default transitions: map parent state Id -> initial child state.
    inits = containers.Map('KeyType', 'double', 'ValueType', 'any');
    for t = allT(:)'
        dst = t.Destination;
        if isempty(t.Source) && ~isempty(dst) && isa(dst, 'Stateflow.State')
            par = dst.getParent;
            if isa(par, 'Stateflow.State') && (par.Id == M.Id || inside(par, M))
                inits(par.Id) = dst;
            end
        end
    end
end

function [ev, gd, ac] = parse_label(L)
    % Split "event [guard] {action}" and drop fprintf/disp from the action.
    L  = strtrim(regexprep(L, '\s+', ' '));
    ev = ''; gd = ''; ac = '';
    ib = strfind(L, '[');  ic = strfind(L, '{');
    if ~isempty(ib) && (isempty(ic) || ib(1) < ic(1))
        ev = strtrim(L(1:ib(1)-1));
        [gd, j] = matched(L, ib(1), '[', ']');
        rest = L(j+1:end);
    elseif ~isempty(ic)
        ev   = strtrim(L(1:ic(1)-1));
        rest = L(ic(1):end);
    else
        ev   = L;
        rest = '';
    end
    ic2 = strfind(rest, '{');
    if ~isempty(ic2), ac = matched(rest, ic2(1), '{', '}'); end
    ac = clean_actions(ac);
    gd = strtrim(gd);
end

function [inner, j] = matched(L, i, op, cl)
    depth = 0;
    for j = i:numel(L)
        if L(j) == op, depth = depth + 1; end
        if L(j) == cl
            depth = depth - 1;
            if depth == 0, inner = L(i+1:j-1); return; end
        end
    end
    inner = L(i+1:end); j = numel(L);
end

function a = clean_actions(a)
    parts = strtrim(strsplit(a, ';'));
    keep = ~cellfun(@isempty, parts) & ~contains(parts, 'fprintf') & ~contains(parts, 'disp(');
    a = strjoin(parts(keep), '; ');
end

function txt = state_actions(s)
    lines = strsplit(s.LabelString, newline);
    body  = regexprep(strjoin(lines(2:end), ' '), '\s+', ' ');
    body  = regexprep(body, '\<en\s*:', 'entry:');
    body  = regexprep(body, '\<du\s*:', 'during:');
    body  = regexprep(body, '\<ex\s*:', 'exit:');
    body  = regexprep(body, 'fprintf\([^;]*\)\s*;?', '');
    body  = regexprep(body, 'disp\([^;]*\)\s*;?', '');
    txt   = strtrim(body);
end


%% ====================================================================
%% Graphviz output (one figure per machine, composites as boxes)
%% ====================================================================
function write_dot(f, M, allS, allJ, edges, inits, mode, wrapN, font, fs, rankdir)
    fid = fopen(f, 'w');
    fprintf(fid, 'digraph "%s" {\n', M.Name);
    fprintf(fid, '  graph [rankdir=%s, compound=true, nodesep=0.45, ranksep=0.8, fontname="%s", fontsize=%d, pad=0.1];\n', rankdir, font, fs);
    fprintf(fid, '  node  [shape=box, style="rounded", fontname="%s", fontsize=%d, margin="0.15,0.06"];\n', font, fs);
    fprintf(fid, '  edge  [fontname="%s", fontsize=%d, arrowsize=0.7];\n', font, fs - 2);
    emit_children(fid, M, allS, allJ, inits, font, fs, '  ');
    for e = edges
        [tailNode, ltail] = endpoint(e.src, allS, inits);
        [headNode, lhead] = endpoint(e.dst, allS, inits);
        lab = e.guard;
        if ~isempty(e.event), lab = strtrim([e.event ' ' lab]); end
        if strcmp(mode, 'full') && ~isempty(e.action)
            lab = strtrim([lab ' {' e.action '}']);
        end
        attrs = sprintf('label="%s"', dotesc(wrap(lab, wrapN)));
        if ~isempty(ltail), attrs = [attrs sprintf(', ltail="%s"', ltail)]; end
        if ~isempty(lhead), attrs = [attrs sprintf(', lhead="%s"', lhead)]; end
        fprintf(fid, '  "%s" -> "%s" [%s];\n', tailNode, headNode, attrs);
    end
    fprintf(fid, '}\n');
    fclose(fid);
end

function emit_children(fid, P, allS, allJ, inits, font, fs, ind)
    % Write P's children; composite children become clusters (recursively).
    if isKey(inits, P.Id)
        fprintf(fid, '%s"__init_%s" [shape=point, width=0.1, label=""];\n', ind, P.Name);
        fprintf(fid, '%s"__init_%s" -> "%s";\n', ind, P.Name, anchor(inits(P.Id), allS, inits));
    end
    for j = allJ(:)'
        if isprop(j, 'Type') && strcmpi(j.Type, 'HISTORY') && isa(j.getParent, 'Stateflow.State') ...
                && j.getParent.Id == P.Id
            fprintf(fid, '%s"H_%s" [shape=circle, label="H", width=0.25, fixedsize=true, fontsize=%d];\n', ...
                ind, P.Name, fs - 2);
        end
    end
    for k = direct_children(P, allS)'
        if isempty(direct_children(k, allS))
            fprintf(fid, '%s"%s" [label="%s"];\n', ind, k.Name, strrep(k.Name, '_', ' '));
        else
            fprintf(fid, '%ssubgraph "cluster_%s" {\n', ind, k.Name);
            fprintf(fid, '%s  label="%s"; style="rounded"; fontname="%s"; fontsize=%d; labeljust="l";\n', ...
                ind, strrep(k.Name, '_', ' '), font, fs);
            emit_children(fid, k, allS, allJ, inits, font, fs, [ind '  ']);
            fprintf(fid, '%s}\n', ind);
        end
    end
end

function [node, cluster] = endpoint(o, allS, inits)
    % Graphviz node for a transition end. Composite states and history
    % junctions are drawn as clusters, so point at a node inside them.
    cluster = '';
    if isa(o, 'Stateflow.Junction')
        par = o.getParent;
        if isprop(o, 'Type') && strcmpi(o.Type, 'HISTORY')
            node = ['H_' par.Name];
        else
            node = anchor(par, allS, inits);
            cluster = ['cluster_' par.Name];
        end
        return
    end
    if isempty(direct_children(o, allS))
        node = o.Name;
    else
        node = anchor(o, allS, inits);
        cluster = ['cluster_' o.Name];
    end
end

function n = anchor(s, allS, inits)
    % A leaf node inside s to attach edges to (follows the initial states).
    while ~isempty(direct_children(s, allS))
        if isKey(inits, s.Id)
            s = inits(s.Id);
        else
            kids = direct_children(s, allS);
            s = kids(1);
        end
    end
    n = s.Name;
end

function s = wrap(s, n)
    words = strsplit(s, ' ');
    lines = {''};
    for w = words
        if strlength(lines{end}) + strlength(w{1}) > n && ~isempty(lines{end})
            lines{end+1} = w{1}; %#ok<AGROW>
        else
            lines{end} = strtrim([lines{end} ' ' w{1}]);
        end
    end
    s = strjoin(lines, '\n');
end

function s = dotesc(s)
    s = strrep(s, '"', '\"');
end


%% ====================================================================
%% LaTeX tables
%% ====================================================================
function write_transition_table(f, name, edges)
    fid = fopen(f, 'w');
    fprintf(fid, '%% Transitions of %s, generated by export_chart_figures.m\n', name);
    fprintf(fid, '%% Needs \\usepackage{booktabs}\n');
    fprintf(fid, '\\begin{tabular}{@{}llp{0.38\\textwidth}p{0.30\\textwidth}@{}}\n\\toprule\n');
    fprintf(fid, 'From & To & Guard & Reset \\\\\n\\midrule\n');
    for e = edges
        guard = e.guard;
        if ~isempty(e.event), guard = strtrim([e.event ' ' guard]); end
        fprintf(fid, '%s & %s & %s & %s \\\\\n', tex(objname(e.src)), tex(objname(e.dst)), ...
            code(guard), code(e.action));
    end
    fprintf(fid, '\\bottomrule\n\\end{tabular}\n');
    fclose(fid);
end

function n = objname(o)
    if isa(o, 'Stateflow.Junction')
        n = [o.getParent.Name ' (H)'];
    else
        n = o.Name;
    end
end

function write_state_table(f, M, allS)
    % All states inside M, composites included, in drawing order.
    fid = fopen(f, 'w');
    fprintf(fid, '%% States of %s, generated by export_chart_figures.m\n', M.Name);
    fprintf(fid, '%% Needs \\usepackage{booktabs}\n');
    fprintf(fid, '\\begin{tabular}{@{}lp{0.70\\textwidth}@{}}\n\\toprule\n');
    fprintf(fid, 'State & Actions \\\\\n\\midrule\n');
    write_state_rows(fid, M, allS, '');
    fprintf(fid, '\\bottomrule\n\\end{tabular}\n');
    fclose(fid);
end

function write_state_rows(fid, P, allS, prefix)
    for k = direct_children(P, allS)'
        fprintf(fid, '%s%s & %s \\\\\n', prefix, tex(k.Name), code(state_actions(k)));
        if ~isempty(direct_children(k, allS))
            write_state_rows(fid, k, allS, '\quad ');
        end
    end
end

function s = code(s)
    if isempty(s), s = '--'; return; end
    s = ['\texttt{' tex(s) '}'];
end

function s = tex(s)
    s = strrep(s, '\', char(1));
    s = regexprep(s, '([&%$#_{}])', '\\$1');
    s = strrep(s, '~', '\textasciitilde{}');
    s = strrep(s, '^', '\textasciicircum{}');
    s = strrep(s, char(1), '\textbackslash{}');
end

function tf = has_graphviz()
    [st, ~] = system('LD_LIBRARY_PATH= dot -V');
    tf = (st == 0);
end