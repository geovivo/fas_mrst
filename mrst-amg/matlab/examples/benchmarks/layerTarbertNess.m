[G, A, q, rock] = getTestCase('dims', [60 220 1], ...
                            'grid', 'cart',...
                            'twistval', 0.01, ...
                            'perm', 'tarbert', ...
                            'layers', 3, ...
                            'stencil',  'tpfa', ...
                            'flow',   'bc', ...
                             'gridaspect', [2 1 10]);
                         
                         
figure(1); clf;
plotCellData(G, log10(rock.perm(:,1)), 'edgec', 'w', 'edgea', .5)
axis tight off

%%
makeProblem = @(interpolator, coarsening) struct('interpolator', interpolator,...
                                                 'coarsening', coarsening);
                                                   
problems = {};

problems = [problems; makeProblem('standard', 'standard')];
% problems = [problems; makeProblem('direct',   'standard')];
% problems = [problems; makeProblem('linear',   'uniform')];
% problems = [problems; makeProblem('unitary',  'pairwise')];

names = {};
for i = 1:numel(problems)
    fprintf('Solving %d of %d\n', i, numel(problems));
    coarse = problems{i}.coarsening;
    interpol = problems{i}.interpolator;
    
    [x, res, meta, partitions] = solveMultigrid(G, A, q,...
                                    'coarsening',       coarse, ...
                                    'interpolator',     interpol,...
                                    'cfstrength',       .25, ...
                                    'maxCoarseSize',    8, ...
                                    'smoother',        'gs', ...
                                    'maxCoarseLevels', 6, ...
                                    'levels',          2, ...
                                    'coarsefactor',    2, ...
                                    'iterations',      100, ...
                                    'verbose',         true,...
                                    'cycleindex',      2);
    problems{i}.res = res;
    problems{i}.meta = meta;
    problems{i}.partitions = partitions;
    names = [names; [coarse, ': ', interpol]];
end


%%
tmp = cellfun(@(x) x.res, problems, 'unif', false);
loglog(horzcat(tmp{:}), '--', 'LineWidth', 2)
grid on
legend(names)
axis tight