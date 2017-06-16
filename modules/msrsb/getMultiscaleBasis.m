function [basis, CG] = getMultiscaleBasis(CG, A, varargin)
%Get multiscale basis functions for a given coarse grid and system matrix
%
% SYNOPSIS:
%   [basis, CG] = getMultiscaleBasis(CG, A, 'type', 'msfv')
%
% REQUIRED PARAMETERS:
%   CG     - Coarse grid.
%
%   A      - System matrix for which the basis functions are to be
%            computed.
%
% OPTIONAL PARAMETERS (supplied in 'key'/value pairs ('pn'/pv ...)):
%   type   - Type of basis functions. Available options are 'MsRSB' for basis
%            functions based on restricted smoothing and 'MsFV' for
%            basis functions based on localized flow problems and a dual
%            grid.
%
%   regularizeSys - Regularize system before computing basis functions, by
%                   ensuring that the row and column sum of the matrix is
%                   zero. Default on.
%
%   iterations - Max number of iterations in MsRSB basis functions. No
%                effect on other solvers.
%
%   tolerance  - Tolerance for MsRSB basis functions.
%
%   implicitDual -  Indicator if the MsFV basis functions are generated
%                   with implicit or explicit dual grid. Implicit generally
%                   makes it easier to generate dual grids, but the basis
%                   construction is no longer local in nature for complex
%                   grids.
%
%  useControlVolume - Use a control volume restriction operator, required
%                     for flux reconstruction. If disabled, will set R =
%                     B^T, i.e. Galerkin/finite element type which will
%                     give better iterative convergence if the coarse scale
%                     stencil is unstable.
%
% RETURNS:
%  basis   - Struct suitable for incompMultiscale. Contains fields .B for
%            basis functions and .R for the restriction operator as well as
%            the name of the method in .type.
%
% SEE ALSO:
%   incompMultiscale

%{
Copyright 2009-2016 SINTEF ICT, Applied Mathematics.

This file is part of The MATLAB Reservoir Simulation Toolbox (MRST).

MRST is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

MRST is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with MRST.  If not, see <http://www.gnu.org/licenses/>.
%}
    G = CG.parent;
    Nc = CG.cells.num;
    Nf = G.cells.num;
    
    opt = struct('type',             'rsb', ...
                 'useMex',           false, ...
                 'regularizeSys',    true, ...
                 'mexGrid',          [], ...
                 'iterations',       ceil(50*(Nf/Nc).^(1/G.griddim)), ...
                 'tolerance',        5e-3, ...
                 'implicitDual',    false, ...
                 'useControlVolume', true);

    opt = merge_options(opt, varargin{:});

    if opt.regularizeSys
        A = (A + A')/2;
        A = A - diag(sum(A, 2));
    end


    switch lower(opt.type)
        case {'msrsb', 'rsb', 'jacobi', 'smoothed', 'jacobi-mex'}
            
            if ~isfield(CG.cells, 'interaction')
                CG = storeInteractionRegion(CG);
            end
            if opt.useMex || strcmpi(opt.type, 'jacobi-mex')
                assert(exist('cppMultiscaleBasis', 'file') > 0, 'MsRSB-Mex basis functions not available');
                CG = setupMexInteractionMapping(CG);
                B = cppMultiscaleBasis(CG, A, 'verbose', true, 'omega', 2/3, 'maxiter', opt.iterations, 'tolerance', opt.tolerance);
            else
                assert(exist('iteratedJacobiBasis', 'file') > 0, 'MsRSB basis functions not available');
                B = iteratedJacobiBasis(A, CG, 'iterations', opt.iterations,...
                    'incrementTol', opt.tolerance);
            end
        case {'mstpfa', 'tpfa'}
            assert(exist('createFaceBasis', 'file') > 0, 'MsTPFA basis functions not available');
            if ~isfield(CG.faces,'region')
                CG = partitionMSTPFA(CG);
            end
            faceb = createFaceBasis(CG, A);
            B = assembleCoarseOperatorsPartition(CG, faceb);
        case {'msfvm', 'msfv'}
            require msfvm
            assert(isfield(CG, 'dual'), 'The MsFV method requires a dual grid!');
            DG = CG.dual;
            if opt.implicitDual
                assert(exist('createMSFVBasis', 'file') > 0, 'Implicit MsFV basis functions not available');
                if ~isfield(DG, 'll')
                    DG.ll = DG.lineedge;
                end
                DG = getDualConstants(CG, DG);
                B = createMSFVBasis(A, DG, false);
            else
                if ~isfield(DG, 'explicit')
                    DG = makeExplicitDual(CG, DG);
                end
                b = constructLocalMSFVBasis(CG, DG, A);
                B = b.B;
            end
        case 'constant'
            B = controlVolumeRestriction(CG.partition)';
        otherwise
            error('Unknown basis function type')
    end

    if opt.useControlVolume
        R = controlVolumeRestriction(CG.partition);
    else
        R = B';
    end

    basis = struct('R', R, 'B', B, 'type', lower(opt.type));
end