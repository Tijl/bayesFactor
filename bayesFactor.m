classdef bayesFactor < handle
    % A class to perform Bayes Factor statistical analysis to quantify
    % evidnce in favor or against a hypothesis.
    % For background see:
    %
    % The mathemetical underpinning for these routines is provided in
    %
    %
    % Implementation notes:
    %  The class currently does not store data, only some default parameers
    %  that are used in different contexts.
    % BK - 2018
    
    properties (SetAccess = public, GetAccess =public)
        %% Default parameters for the Monte Carlo integration.
        minG = 0.0001;
        maxG = 10000;
        stepG = 0.05;
        nrSamples = 10000;
        nDimsForMC = 3; % If there are this many dimensions, use MC integration
        % 1 and 2D integration work fine with standard
        % integral.m but 3d is slow and higher not
        % possible.
    end
    
    %% Public acces functions - the main interface
    methods (Access=public)
        
        function o = bayesFactor
            % Constructor. Nothing to do.
            
        end
        
        function [results] = designAnalysis(o,varargin)
            % Perform a Bayes Factor Design Analysis.
            %  This function will simulate data sets with a given effect
            %  size, analyze  them using the test that is specified and
            %  plot a historgram of BayesFactors under the null hypothesis
            %  (effect size =0) and the H1 hypothesis (effect size is as
            %  specified).
            %
            % Parm/Value pairs:
            %
            % N = Sample size: can be a vector
            % sequential = Simulate a sequential Bayes Design (in this
            %               design an increasing number of samples (N) is analyzed, and te
            %               experiment stops when the Bayes Factor reaches a
            %               pre-specified thredhold for either H1 or H0.
            %               [false].
            % evidenceBoundary = Boundary at which to stop collecting more
            %                   samples. This should contain two elements,
            %                   the threshold below which the evidence for H0 is
            %                   considered sufficient and the threshold above
            %                  which the evidence for H1 is considered sufficient. [1/6 6].
            % nrMC  =   The number of monte carlo simulations to run [10000]
            % test  = Which statistical test to use. TTEST, TTEST2,RMANOVA
            % effectSize = The (expected) effectSize under H1. The "units" differ per test:
            %                   TTEST,TTEST2: expressed as fraction of the standard deviation. [0.5]
            %                   LINEARMIXEDMODEL: expected coefficients in
            %                   the linear model in the order corresponding
            %                   to the design matrix.
            %                   To specify a distribution of effectSizes,
            %                   use an anonymouys function. For instance,
            %                   for an effect size with a mean of 0.5 and stdev of 0.1,
            %                   pass @(N) (0.5_0.1*randn([N 1]])
            % designMatrix = The design matrix for a linear mixed model.
            %
            % tail = Tail for TTest/TTest2. [both]
            % scale = SCale of the Cauchy prior [sqrt(2)/2].
            % pSuccess = The target probability of "success" (reaching the
            % evidence boundary). [0.9]
            % linearModel = The linear model to simulate. Only used
            % for ANOVA test
            % plot = Toggle to show graphical output as in Schoenbrodt &
            %                   Wagenmakers
            %
            %
            % To add your own analysis, but reuse the looping/graphing from
            % this funcition, set 'test' to 'SPECIAL' and provide
            % 'dataFun', functions that generate data
            % based on an effect size and N, and 'bfFun', a function that
            % cacluates the bayesFactor based on the output of the dataFun.
            % Check the code for TTEST etc. below for examples of
            % dataFun/bfFun.
            %
            % For a tutorial on BFDA, see
            %           Schoenbrodt, F. D. & Wagenmakers, E. J.
            %           Bayes factor design analysis: Planning for compelling evidence.
            %           Psychon. Bull. Rev. 1�15 (2017). doi:10.3758/s13423-017-1230-y
            %
            % OUTPUT
            % A struct contining structs H1 and H0. They contain information on the simulations
            % under H1 and H0, respectively. The content is different when
            % a sequential verus a fixed design is used:
            % FIXED N Design
            %   .bf.all = The BayesFactor for each simulation and each N [nrMC nrDifferentSampleSizes]
            %   .bf.median = Median bayesfactor, for each N.
            %   .N.min  = This is the smalest sample size (out of the vector provided as input 'N') for which the
            %               probability of the evidence reaching the evidence boundary is 'pSuccess' (an input parm)
            %   .N.median = NaN (not used in Fixed-N)
            %   .N.pMax = NaN (not used in Fixed-N)
            % .pFalse - Propbabilty of misleading evidence (false positive
            % for H0, false negative for H1).
            % SEQUENTIAL design
            %  .bf.all = The bayes factor for each simulation and each
            %  sequential sample size . Each row represents an experiment
            %  with increasing sample sizes. The sequence stops when an
            %  evidence boundary is reached.  (bf will be NaN for larger
            %  sample sizes in that row.)
            % .bf.median = NaN = not used in sequential
            % .N.all = The distribution of sample sizes
            % N.median  = the mean sample size used in the sequential
            %               design (median across all sequences that hit an
            %               evidence boundary an dthose that reached n-max)
            % N.pMax = probablity of terminatinng at n-max (i.e. not
            % hitting an evidence boundary before N =n-Max).
            % N.min = NaN - not used in a sequential design.            %
            % % .pFalse - Propbabilty of misleading evidence (false positive
            % for H0, false negative for H1).
            %
            % EXAMPLES:
            %  Explore the power of a one sample T test with 20 or 100 subjects:
            %   This will create a figure like Figure #3 in Schoenbrodt &
            %   Wagenmakers.
            %       o = bayesFactor; % Create a bf object
            %       designAnalysis(o,'N',[20 100],'test','ttest','sequential',false);
            %
            % Investigate a sequential sampling design where we obtain
            % up to 200 samples but stop data collection if a BF10 of 1/6
            % or 6 is reached. (The example illustrates that sample size
            % spacing does not have to be regular
            %    o = bayesFactor;
            %    designAnalysis(o,'N',[20:2:60 65:5:120 130:10:200],'evidenceBoundary',[1/6 6],'test','ttest','sequential',true,'nrMC',1000);
            %
            % BK - Jan 2019
            
            p = inputParser;
            p.addParameter('N',[20 100]); % A vector of sample sizes to evaluate
            p.addParameter('sequential',false); % Toggle to use a sequential design [false]
            p.addParameter('nrMC',10000); % Each N is evaluated this many time (Monte Carlo)
            p.addParameter('evidenceBoundary',[1/6 6]);
            p.addParameter('pSuccess',0.9); % For a fixed-N design, which fraction of success (i.e. reaching the h1 evidence boundary) is acceptable (used to calculate minimalN)
            p.addParameter('test','TTEST');  % Select one of TTEST, TTEST2, RMANOVA,ANOVA, SPECIAL
            p.addParameter('effectSize',0.5);
            p.addParameter('linearModel',[]); % Used only for linearModel
            p.addParameter('tail','both');
            p.addParameter('scale',sqrt(2)/2);
            p.addParameter('plot',true);
            p.addParameter('bfFun',[]);  % For 'test'=='SPECIAL' - specify your own bfFun and dataFun here.
            p.addParameter('dataFun',[]);
            p.parse(varargin{:});
            results.H1 = struct('N',struct('min',NaN,'median',NaN,'all',[],'pMax',NaN),'bf',struct('all',[],'median',nan),'pFalse',[]);
            results.H0 = results.H1;
            % Depending on the test, create anonymous functions that will
            % generate simulated data aand call the appropriate BF function
            % in the MonteCarlo loop below.
            switch upper(p.Results.test)
                case 'TTEST'
                    % BFDA for a one-sample ttest.
                    dataFun = @(effectSize,N) ({effectSize + randn([N 1])});
                    bfFun = @(X) bayesFactor.ttest(X,'tail',p.Results.tail,'scale',p.Results.scale);
                case 'TTEST2'
                    % Two sample ttest
                    dataFun = @(effectSize,N) ({-0.5*effectSize + randn([N 1]),0.5*effectSize + randn([N 1])});
                    bfFun = @(X,Y) bayesFactor.ttest2(X,Y,'tail',p.Results.tail,'scale',p.Results.scale);
                case 'RMANOVA'
                    %Repeated measures ANOVA
                    dataFun = @(effectSize,N) o.simulateLinearModel(p.Results.linearModel,effectSize,N);
                    bfFun   = @(X,Y) o.linearModel(X,Y);
                case 'SPECIAL'
                    % User specified functions to generate simulated data
                    % and calculate the bf
                    dataFun = p.Results.dataFun;
                    bfFun = p.Results.bfFun;
                otherwise
                    errror(['BFDA for ' p.Results.testFun ' has not been implemented yet'])
            end
            
            % Initialize
            nrN = numel(p.Results.N);
            results.H1.bf.all = nan(p.Results.nrMC,nrN);
            results.H0.bf.all = nan(p.Results.nrMC,nrN);
            maxN = max(p.Results.N);
            upperBF = max(p.Results.evidenceBoundary);
            lowerBF = min(p.Results.evidenceBoundary);
            
            if p.Results.sequential
                % Run a sequential design :  generate fake data for maxN
                % subjects but sample htese successively and at each step
                % test whether the BF is above threshold (and if so,
                % terminate). Repeat this nrMC times.
                nFalsePositive = 0;
                nFalseNegative = 0;                    
                for j=1:p.Results.nrMC
                    if isa(p.Results.effectSize,'function_handle')
                        es = p.Results.effectSize(maxN);
                    else
                        es = p.Results.effectSize;
                    end
                    data  = dataFun(es,maxN);
                    nullData  = dataFun(0,maxN);
                    for i=1:nrN
                        % Sequential sampling for H1 data
                        thisData = cellfun(@(x)(x(1:p.Results.N(i))),data,'UniformOutput',false);
                        results.H1.bf.all(j,i) = bfFun(thisData{:});
                        if results.H1.bf.all(j,i) > upperBF || results.H1.bf.all(j,i) < lowerBF
                            % Crossed threshold. Stop sampling.
                            if results.H1.bf.all(j,i) <lowerBF
                                nFalseNegative= nFalseNegative+1;
                            end
                            break;
                        end
                    end
                    for i=1:nrN
                        % Sequential sampling for HO data
                        thisNullData = cellfun(@(x)(x(1:p.Results.N(i))),nullData,'UniformOutput',false);
                        results.H0.bf.all(j,i) = bfFun(thisNullData{:});
                        if results.H0.bf.all(j,i) >upperBF|| results.H0.bf.all(j,i) < lowerBF
                            % Crossed threshold. Stop sampling.
                            if results.H0.bf.all(j,i) >upperBF
                                nFalsePositive= nFalsePositive+1;
                            end
                            break;
                        end
                    end
                end
                % Analyze the results to determine how many samples will
                % be collected
                [ix,col] = find(isnan(results.H1.bf.all)');
                [~,isFirst] =unique(col);
                nrSamplesEarlyStop  = p.Results.N(ix(isFirst));
                nrMax = p.Results.nrMC- numel(isFirst);
                results.H1.N.all = [nrSamplesEarlyStop maxN*ones(1,nrMax)];
                results.H1.N.median = median(results.H1.N.all);
                results.H1.pFalse  = nFalseNegative./p.Results.nrMC;
                results.H1.N.pMax = nrMax./p.Results.nrMC;
                
                [ix,col] = find(isnan(results.H0.bf.all)');
                [~,isFirst] =unique(col);
                nrSamplesEarlyStop  = p.Results.N(ix(isFirst));
                nrMax = p.Results.nrMC- numel(isFirst);
                results.H0.N.all = [nrSamplesEarlyStop maxN*ones(1,nrMax)];
                results.H0.N.median = median(results.H0.N.all);
                results.H0.pFalse  = nFalsePositive./p.Results.nrMC;
                results.H0.N.pMax = nrMax./p.Results.nrMC;
                
            else
                % Simualte a regular fixed N design
                for i =1:nrN
                    for j= 1:p.Results.nrMC
                        if isa(p.Results.effectSize,'function_handle')
                            es = p.Results.effectSize(p.Results.N(i));
                        else
                            es = p.Results.effectSize;
                        end
                        data  = dataFun(es,p.Results.N(i));
                        results.H1.bf.all(j,i) = bfFun(data{:}); % Collect BF under H1
                        nullData  = dataFun(0,p.Results.N(i));
                        results.H0.bf.all(j,i) = bfFun(nullData{:}); % Collect BF under H0
                    end
                end
                % Calculate the minimum number of samples needed to reach
                % H1 evidence boundary in p.Restuls.fractionSuccess of the
                % experiments
                ix  = mean(results.H1.bf.all>upperBF)>p.Results.pSuccess; %
                results.H1.N.min = min(p.Results.N(ix));
                ix  = mean(results.H0.bf.all<lowerBF)>p.Results.pSuccess; %
                results.H0.N.min = min(p.Results.N(ix));
                results.H0.pFalse =  nanmean(results.H0.bf.all>upperBF);  % Upper evidence boundary under H0 = false positives
                results.H1.pFalse =  nanmean(results.H1.bf.all<lowerBF);  % Lower evidence boundary under H1 - false negatives
                results.H0.bf.median  = median(results.H0.bf.all);
                results.H1.bf.median = median(results.H1.bf.all);
                
            end
            
            
            
            % If requested show graphs
            if p.Results.plot
                
                ticks= ([1/10 1/3 1  3 10 30 10.^(2:8)] );
                tickLabels = {'1/10','1/3', '1',' 3','10','30','100','1000','10^4','10^5','10^6','10^7','10^8'};
                clf;
                if p.Results.sequential
                    % Show the "trajectories"  - BF as a funciton of sample
                    % size , terminating at the boundaries.
                    R =2;C=1;
                    out = ticks<lowerBF | ticks>upperBF;
                    ticks(out)=[];
                    tickLabels(out) =[];
                    for i=0:1
                        subplot(R,C,1+i);
                        if i==0
                            toPlot = results.H1.bf.all;
                            hyp ='H1';
                            if isa(p.Results.effectSize,'function_handle')
                                es = func2str(p.Results.effectSize);
                            else
                                es = num2str(p.Results.effectSize);
                            end
                        else
                            toPlot = results.H0.bf.all;
                            hyp = 'H0';
                            es = '0';
                        end
                        toPlot(toPlot>upperBF) = upperBF;
                        toPlot(toPlot<lowerBF) = lowerBF;
                        plot(p.Results.N,toPlot','Color',0.5*ones(1,3))
                        hold on
                        plot([1 maxN],upperBF*ones(1,2),'k--')
                        plot([1 maxN],lowerBF*ones(1,2),'k--')
                        plot(repmat([1 maxN]',[1 numel(ticks)]), repmat(ticks,[2 1]),'k:')
                        set(gca,'YScale','Log','YLim',[lowerBF*0.8 upperBF*1.2],'YTick',ticks,'YTickLabels',tickLabels)
                        xlabel 'Sample Size'
                        ylabel 'Bayes Factor (BF_{10})'
                        title (['Under ' hyp ': Effect Size= ' es]);
                        h1Boundary  = mean(max(toPlot,[],2)>=upperBF);
                        text(min(p.Results.N),1.1*upperBF,sprintf('%d%% stopped at H1 Boundary',round(100*h1Boundary)),'FontWeight','Bold');
                        h0Boundary = mean(min(toPlot,[],2)<=lowerBF);
                        text(min(p.Results.N),0.9*lowerBF,sprintf('%d%% stopped at H0 Boundary',round(100*h0Boundary)),'FontWeight','Bold');
                    end
                    h = annotation(gcf,'textbox',[0.3 0.95 0.4 0.025],'String',['BFDA: ' p.Results.test ' (nrMC = ' num2str(p.Results.nrMC) ')']);
                    h.HorizontalAlignment = 'Center';
                else
                    % 1 or more fixed N designs.
                    % Show evidence histograms for each N (columns) under H1 (top
                    % row) and under H0 (bottom row).
                    C =nrN;
                    R =2;
                    nrBins = p.Results.nrMC/50;
                    maxlBf = round(log10(prctile(results.H1.bf.all(:),99)));
                    minlBf = round(log10(prctile(results.H0.bf.all(:),1)));
                    bins= linspace(minlBf,maxlBf,nrBins);
                    out = log10(ticks)<minlBf | log10(ticks)>maxlBf;
                    
                    ticks(out)=[];
                    tickLabels(out) =[];
                    for j=0:1
                        if j==0
                            toPlot = results.H1.bf.all;
                            hyp ='H1';
                            if isa(p.Results.effectSize,'function_handle')
                                es = func2str(p.Results.effectSize);
                            else
                                es = num2str(p.Results.effectSize);
                            end
                        else
                            toPlot = results.H0.bf.all;
                            hyp = 'H0';
                            es = '0';
                        end
                        for i=1:nrN
                            subplot(R,C,C*j+i);
                            [n,x] = hist(log10(toPlot(:,i)),bins);
                            plot(10.^x,n./sum(n))
                            set(gca,'XTick',ticks,'XTickLabel',tickLabels,'XScale','Log')
                            hold on
                            xlabel 'Bayes Factor (BF_{10})'
                            ylabel 'Density'
                            title([ hyp ': N = ' num2str(p.Results.N(i)) ', Effect Size = ' es]);
                        end
                    end
                    % Equal x-axes
                    allAx = get(gcf,'Children');
                    xlims = get(allAx,'XLim');
                    xlims = cat(1,xlims{:});
                    set(allAx,'XLim',[round(min(xlims(:,1))) round(max(xlims(:,2)))]);
                    h = annotation(gcf,'textbox',[0.3 0.95 0.4 0.025],'String',...
                        ['BFDA: ' p.Results.test ' (nrMC = ' num2str(p.Results.nrMC) ') Minimal N for ' num2str(p.Results.pSuccess*100) '% success = ' num2str(results.H1.N.min) ]);
                    h.HorizontalAlignment = 'Center';
                    for i=allAx(:)'
                        % Show evidence boundary
                        plot(i,repmat(p.Results.evidenceBoundary,[2 1]),repmat(ylim(i)',[1 size(p.Results.evidenceBoundary,2)]),'k--')
                    end
                end
            end
        end
        
        
        
        function [bf10,lm] = anova(o,x,y,varargin)
            % Function to analyze an N-way ANOVA with fixed and/or random effects
            %
            % INPUT
            %  The user can provide the data as output of fitlme (i.e. a linear
            %  mixed model)
            %  x = a LinearMixedModel from the stats toolbox (created by
            %  fitlme).
            % OR the user can provide a table and a formula
            %  x = A table
            %  y = A Wilkinson notation formula.
            %
            % Parm/Value pairs:
            % 'sharedPriors' - Which columns (i.e. factors) in the table should share a
            %                   their prior on their effect size. The default is that
            %                   all levels within a factor share a prior.
            %                   To share priors across factors, use
            %                      {{'a','b'},{'c','d'}}   -> share priors for a and b
            %                       and, separately, for c and d.
            %                      {{'a','b','c','d'}} ->  share priors for all factors
            %                      (this is the 'single g' approach in Rouder.
            %                      Shortcuts:
            %                       'within' - share within a fixed effect factor, not across
            %                       'singleG' - share across all fixed effects.
            % 'treatAsRandom' - Factors to be treated as random effects.
            %
            % OUTPUT
            % bf10 - The Bayes Factor comparing the model to the model with intercept only.
            %       To compute BF for more refined hypotheses you compute
            %       a BF for the full model, and a restricted model and
            %       then take the ratio. See rouderFigures for examples.
            % lm  = The linear mixed model.
            %
            % BK -2018
            
            if isa(x,'LinearMixedModel')
                lm = x;
                if nargin<=2
                    args = {};
                else
                    args = cat(2,{y},varargin); % Y must be part of the vararing
                end
            elseif isa(x,'table') && ischar(y)  % Specified a table and formula
                lm = fitlme(x,y);
                args = varargin;
            else
                error('bayesFactor.anova requires either a LinearMixedModel or a Table & Formula as its input');
            end
            p=inputParser;
            p.addParameter('sharedPriors','within',@(x) ischar(x) || (iscell(x) && iscell(x{1}))); % Cell containing cells with factors(columns) that share a prior.
            p.addParameter('treatAsRandom',{});
            p.parse(args{:});
            
            
            f=lm.Formula;
            if ~isempty(f.GroupingVariableNames)
                error('Not implemented yet');
            end
            
            allTerms = bayesFactor.getAllTerms(lm);
            % Construct the design matrix
            [X,y] = designMatrix(o,lm,allTerms,'zeroSumConstraint',true,'treatAsRandom',p.Results.treatAsRandom);
            nrAllTerms = numel(allTerms);
            
            % Setup sharing of priors as requested
            if ischar(p.Results.sharedPriors)
                switch upper(p.Results.sharedPriors)
                    case 'WITHIN'
                        % Share priors for each level of each factor, but not across factors
                        sharedPriors = cell(1,nrAllTerms);
                        [sharedPriors{:}] = deal(allTerms{:});
                    case 'SINGLEG'
                        sharedPriors = {allTerms};
                    case {'NONE',''}
                        sharedPriors ={};
                end
            else
                sharedPriors = p.Results.sharedPriors;
            end
            sharedPriorIx = cell(1,numel(sharedPriors));
            [sharedPriorIx{:}] = deal([]);
            
            % Assign groups of effects to use the same prior on effect size.
            soFar  =0;
            if isempty(sharedPriors)
                sharedPriorIx = {};
            else
                for i=1:numel(allTerms)
                    match = cellfun(@any,cellfun(@(x)(strcmp(allTerms{i},x)),sharedPriors,'UniformOutput',false));
                    if ~any(match)
                        error(['Shared priors not defined for ' allTerms{i}]);
                    end
                    nrInThisTerm  = size(X{i},2);
                    sharedPriorIx{match} = cat(2,sharedPriorIx{match},soFar+(1:nrInThisTerm));
                    soFar = soFar+nrInThisTerm;
                end
            end
            %% Call the nWayAnova function for the actual analysis
            X= [X{:}];
            bf10 = o.nWayAnova(y,X,'sharedPriors',sharedPriorIx);
        end
        
        
        
        
        
    end
    
    %% Internal computations.
    methods (Access = protected)
        
        function [X,y] = designMatrix(o,lm,allTerms,varargin)
            % Extract a dummy encoded design matix from a linear model .
            % All variables are assumed to be categorical.
            % INPUT
            % lm =  A linear mixed efffects model
            % allTerms = A cell array of variable names to include int he
            % design arrrag ( e.g. {'ori','freq','ori:freq'} for two mains and an interaction)
            % Parm/Value
            % ZeroSumConstraint -  Toggle to apply the zero sum constraint to
            %                   each factor (This equates the marginal prior across terms in the
            %                           factor; see Rouder et al) [true]
            % treatAsRandom  - A cell array of factors which should be
            %               treated as random (i.e. not fixed) effects.
            %               [{}].
            % OUTPUT
            % X = The design matrix [nrObservations nrLevels]
            % y = The response data
            % BK - 2019.
            
            p = inputParser;
            p.addParameter('zeroSumConstraint',true,@islogical);
            p.addParameter('treatAsRandom',{},@iscell);
            p.parse(varargin{:});
            
            nrAllTerms =numel(allTerms);
            X = cell(1,nrAllTerms);
            isCategorical=  ~ismember(lm.Variables.Properties.VariableNames,lm.ResponseName);
            opts = {'model','linear','categoricalvars',isCategorical,'intercept',false,'DummyVarCoding','full','responseVar',lm.ResponseName};
            for i=1:nrAllTerms
                if any(allTerms{i}==':')
                    % An interaction term.
                    aName =extractBefore(allTerms{i},':');
                    bName = extractAfter(allTerms{i},':');
                    thisA = classreg.regr.modelutils.designmatrix(lm.Variables,'PredictorVars',aName,opts{:});
                    thisB = classreg.regr.modelutils.designmatrix(lm.Variables,'PredictorVars',bName,opts{:});
                    if ~ismember(aName,p.Results.treatAsRandom) && p.Results.zeroSumConstraint
                        thisA = o.zeroSumConstraint(thisA);
                    end
                    if ~ismember(bName,p.Results.treatAsRandom) && p.Results.zeroSumConstraint
                        thisB = o.zeroSumConstraint(thisB);
                    end
                    thisX = o.interaction(thisA,thisB);
                else
                    % A main term
                    thisX = classreg.regr.modelutils.designmatrix(lm.Variables,'PredictorVars',allTerms{i},opts{:});
                    % Sum-to-zero contrasts that equates marginal priors across levels.
                    if p.Results.zeroSumConstraint
                        thisX = o.zeroSumConstraint(thisX);
                    end
                end
                X{i} =thisX; % Store for later use
            end
            if nargout>1
                y= lm.Variables.(lm.ResponseName);
            end
        end
        
        
        function v = mcIntegral(o,fun,prior,nrDims)
            % Monte Carlo integration
            %
            % INPUT
            % fun -  The function to integrate. This should be specified as a
            %       function_handle that takes a single input (g)
            % prior - the prior distribution of the g's. A function_handle.
            %
            % nrDims - The number of dimensions to integrate over. [1]
            % options - A struct with options.  []
            % OUTPUT
            % v -  The value of the integral. (Typically the BF10).
            
            
            %% Setup the PDF to do importance sampling
            gRange =  o.minG:o.stepG:o.maxG;
            pdf = prior(gRange);
            pdf = pdf./sum(pdf);
            % Draw samples weighted by this prior.
            g =nan(nrDims,o.nrSamples);
            for d=1:nrDims
                g(d,:) = randsample(gRange,o.nrSamples,true,pdf);
            end
            %% Evaluate the function at these g values
            bf10Samples = fun(g);
            pg = prod(prior(g),1);  % Probability of each g combination
            v = mean(bf10Samples./pg); % Expectation value- = integral.
        end
        
        
        function bf10 = nWayAnova(o,y,X,varargin)
            % ANOVA BF
            % y = data values
            % X = design matrix for ANOVA (indicator vars)  no constant term
            %
            % Parm/Value pairs
            % 'sharedPriors'  - Cell array of vectors indicating which effects (columns
            % of X) share the same prior. [{1:nrEffects}]: all effects share the same prior.
            %
            % BK 2018
            nrEffects = size(X,2);
            
            p =inputParser;
            p.addParameter('sharedPriors',{},@iscell); % Which effects share a prior? A cell array with indices corresponding to columns of X
            p.parse(varargin{:});
            
            if isempty(p.Results.sharedPriors)
                sharedPriors = {1:nrEffects};
            else
                sharedPriors = p.Results.sharedPriors;
            end
            
            prior = @(g)(bayesFactor.scaledInverseChiPdf(g,1,1));
            integrand = @(varargin) (bayesFactor.rouderS(cat(1,varargin{:}),y,X,sharedPriors).*prod(prior(cat(1,varargin{:})),1));
            nrDims = numel(sharedPriors);
            if nrDims>= o.nDimsForMC
                % Use MC Sampling to calculate the integral
                bf10 = o.mcIntegral(integrand,prior,nrDims);
            else
                switch (nrDims)
                    case 1
                        bf10 = integral(integrand,0,Inf);
                    case 2
                        bf10 = integral2(integrand,0,Inf,0,Inf);
                    case 3
                        bf10 = integral3(integrand,0,Inf,0,Inf,0,Inf);
                end
            end
        end
        
        function out = simulateLinearModel(o,lm,effectSize,N)
            % Simulate data based on a linear model vector specifying the mean
            % for  each level of each factor and the number of samples to
            % generate.
            % lm = A linearMixedModel that specifies the base model for a
            % single sample/subject.
            % effectSize = A vector with the mean of each factor and level
            % (e.g. for two factors (a,b) with 2 and 3 levels respectively,
            % specify the effectSize as  [a1 a2 b1 b2 b3].
            % N = How many observations to generate. Note that N=1 means
            % one observation for each of the combinations (i.e. 6 for the
            % example).
            X = designMatrix(o,lm,bayesFactor.getAllTerms(lm),'zeroSumConstraint',false,'treatAsRandom',{});
            X = [X{:}];
            if numel(effectSize)==1
                effectSize = effectSize*ones(1,size(X,2));
            end
            if size(X,2) ~= numel(effectSize)
                error('Please specify effect size for the linear model as one coefficient for each column in the deisgn matrix');
            end
            y =  repmat(X,[N 1])*effectSize(:)+randn([N*size(X,1) 1]);
            
            tbl = table(y,'variablenames',{lm.ResponseName});
            for i=1:lm.NumPredictors
                tbl = addvars(tbl,repmat(lm.Variables.(lm.PredictorNames{i}),[N 1]),'newvariablenames',{lm.PredictorNames{i}});
            end
            out = {tbl,char(lm.Formula)};
        end
    end
    
    %% Helper functions
    methods (Static, Hidden)
        function G = gMatrix(grouping,g)
            % Generate a matrix in which each row corresponds to an effect, each column a value
            % that will be integrated over. The grouping cell array determines which of
            % the effects share a prior (i.e. levles of the same factor) and which have
            % their own.
            % grouping   - Cell array with vectors that contain effect indices (i.e.
            % columns of the design%matrix) that share a prior.
            % g  - The values for each of the priors. Each row is an independent prior,
            %               each column is a sample
            %
            % EXAMPLE
            % gMatrix({1 2],[3 4]},[0 0.1 0.2 0.3; 0.6 0.7 0.8 0.9])
            % g = [ 0 0.1 0.2 0.3;
            %       0 0.1 0.2 0.3;
            %       0.6 0.7 0.8 0.9;
            %       0.6 0.7 0.8 0.9]
            
            
            nrEffects = sum(cellfun(@numel,grouping));
            assert(nrEffects>0,'The number of groups must be at least one');
            nrValues = size(g,2);
            G = nan(nrEffects,nrValues);
            for i=1:numel(grouping)
                G(grouping{i},:) = repmat(g(i,:),[numel(grouping{i}) 1]);
            end
        end
        
        function value= rouderS(g,y,X,grouping)
            % The S(g) function of Eq 9 in Rouder et al.
            % g = Matrix of g values, each row is an effect, each column is a value
            % that we're integrating over.
            % y = Data values
            % X = design matrix, without a constant term, with indicator variables only
            
            g = bayesFactor.gMatrix(grouping,g);
            
            nrObservations = size(X,1);
            one = ones(nrObservations,1);
            P0 = 1./nrObservations*(one*one');
            yTilde = (eye(nrObservations)-P0)*y;
            XTilde = (eye(nrObservations)-P0)*X;
            nrPriorValues=size(g,2);
            value= nan(1,nrPriorValues);
            for i=1:nrPriorValues
                if all(g(:,i)==0)
                    value(i)=0;
                else
                    G = diag(g(:,i));
                    invG = diag(1./g(:,i));
                    Vg = XTilde'*XTilde + invG;
                    yBar = one'*y/nrObservations;
                    preFactor= 1./(sqrt(det(G))*sqrt(det(Vg)));
                    numerator =    y'*y-nrObservations*yBar^2;
                    denominator = ((yTilde'*yTilde) -yTilde'*XTilde*(Vg\XTilde'*yTilde));
                    value(i)= preFactor*(numerator/denominator).^((nrObservations-1)/2);
                end
            end
        end
        
        
        function [Xa,Qa] = zeroSumConstraint(X)
            % Impose a zero-sum constraint on a dummy coded predictor matrix X
            % as in Rouder et al. 2012 . The goal is to make the model estimable
            % while equating marginal priors across levels.
            %
            % By default this is applied to all fixed effects.
            %
            % INPUT
            % X = Dummy coded predictor Matrix [nrObservations nrLevels].
            %       By passing a scalar, the function computes only the projection
            %       matrix (Qa) for a predictor matrix with that many effects.
            % OUTPUT
            % Xa = Matrix with zero-sum constraint [nrObservations nrLevels-1]
            % Qa -  projection matrix (Xa = X*Qa).
            %
            % BK - 2018
            
            if isscalar(X)
                % This is the number of effects
                nrEffects = X;
            else
                %Design matrix was passed
                nrEffects = size(X,2);
            end
            
            %% Follow  Rouder et al. 2012
            Sigmaa =eye(nrEffects)- ones([nrEffects nrEffects])/nrEffects;
            [eigenVecs,ev]= eig(Sigmaa','vector');
            [~,ix] = sort(ev,'desc');
            Qa = eigenVecs(:,ix(1:end-1));
            %Iaminus1 = eye(nrEffects-1);
            %Sigmaa = Qa*Iaminus1*Qa';
            if isscalar(X)
                Xa =[];
            else
                % Transform design matrix
                Xa = X*Qa;
            end
            
        end
        
        function interactions = allInteractions(factorNames)
            % Given a cell array of factor names, create all pairwise combinations
            % of factors to represent interactions
            % INPUT
            % factorNames  - cell array of names
            % OUTPUT
            % interactionNames - cell array of interaction names
            %
            % allInteractions({'a','b'}) -> {'a:b'}
            %
            % BK  -Nov 2018
            
            cntr=0;
            nrFactors = numel(factorNames);
            nrInteractions = nrFactors*(nrFactors-1)-1;
            interactions =cell(1,nrInteractions);
            for i=1:nrFactors
                for j=(i+1):nrFactors
                    cntr= cntr+1;
                    interactions{cntr} = [factorNames{i} ':' factorNames{j}];
                end
            end
        end
        
        function X = interaction(Xa,Xb)
            % Create all interaction terms from two dummy coded design matrices.
            % (See Box II in Rouder et al. 2012)
            %
            % INPUT
            % Xa, Xb = [nrObservations nrA] and [nrObservations nrB]
            %           design matrices with matching number of observation (rows)
            % OUTPUT
            % X = Dummy coded design matrix [nrObservations nrA*nrB]
            %
            nA = size(Xa,2);
            nB = size(Xb,2);
            Xa = repmat(Xa,[1 nB]);
            Xb = repmat(Xb,[1 nA]);
            ix = (repmat(1:nA:nA*nB,[nA 1]) + repmat((0:nA-1)',[1 nB]))';
            Xa = Xa(:,ix(:));
            X= Xa.*Xb;
            
        end
        
        
        function y = inverseGammaPdf(x,alpha,beta)
            % The inverse Gamma PDF.
            % INPUT
            % x  (>0)
            % alpha - shape parameter
            % beta  - scale parameter
            %
            % BK - 2018
            %assert(all(x>0),'The inverse gamma PDF is only defined for x>0')
            z = x<0;
            y = zeros(size(z));
            y(~z) = (beta.^alpha)/gamma(alpha)*(1./x(~z)).^(alpha+1).*exp(-beta./x(~z));
        end
        
        function y = scaledInverseChiPdf(x,df,scale)
            % The Scaled Inverse Chi-Squared Distribution.
            % INPUT
            % x = the parameter value
            % df = degrees of freedom
            % scale = scale (tau squared).
            % OUTPUT
            % y = The probaility density
            %
            % BK - 2018
            %assert(all(x>0),'The scaled inverse Chi-squared PDF is only defined for x>0')
            z = x<0;
            y = zeros(size(z));
            if nargin <3
                scale =1; % Default to scaled inverse Chi-squared.
            end
            y(~z) = bayesFactor.inverseGammaPdf(x(~z),df/2,df*scale/2);
        end
        
    end
    
    %% Public User interface
    methods (Static, Hidden=false)
        function [bf10,p,CI,stats] = ttest2(X,Y,varargin)
            % Calculates Bayes Factor for a two-sample t-test.
            % X - Sample 1
            % Y - Sample 2 (not necessarily of the same size)
            %
            % Optional Parm/Value pairs:
            % alpha - significance level for the frequentist test. [0.05]
            % tail - 'both','right', or 'left' for two or one-tailed tests [both]
            %               Note that  'right' means X>Y and 'left' is X<Y
            % scale - Scale of the Cauchy prior on the effect size  [sqrt(2)/2]
            % stats - A struct containing .tstat  , .df , .pvalue .tail and .N - This allows one to
            %               calculate BF10 directly from the results of a standard ttest2 output.
            %           Note, however, that .N should be adjusted to nX*nY/(nX+nY) ,
            %           and                 .df = nx+ny-2
            %           If you call this fuction with data (X, Y) this adjustment is
            %           done automatically.
            %
            % OUTPUT
            % bf10 - The Bayes Factor for the hypothesis that the means of the samples are different
            % p     - p value of the frequentist hypothesis test
            % CI    - Confidence interval for the true mean of X
            % stats - Structure with .tstat, .df,resulting from the traditional test.
            %
            % Internally this code calls bf.ttest for the computation of Bayes Factors.
            %
            %
            % BK - Nov 2018
            
            if isnumeric(X)
                parms = varargin;
            else
                %Neither X nor Y specified (this must be a call with 'stats' specified
                parms = cat(2,{X,Y,},varargin);
                X=[];Y=[];
            end
            
            p=inputParser;
            p.addParameter('alpha',0.05);
            p.addParameter('tail','both',@(x) (ischar(x)&& ismember(upper(x),{'BOTH','RIGHT','LEFT'})));
            p.addParameter('scale',sqrt(2)/2);
            p.addParameter('stats',[],@isstruct);
            p.parse(parms{:});
            
            if isempty(p.Results.stats)
                % Calculate frequentist from the X and Y data
                tail = p.Results.tail;
                [~,p,CI,stats] = ttest2(X,Y,'alpha',p.Results.alpha,'tail',tail);
                nX = numel(X);
                nY = numel(Y);
                statsForBf = stats;
                statsForBf.p = p;
                statsForBf.N = nX*nY/(nX+nY);
                statsForBf.df = nX+nY-2;
                statsForBf.tail = tail;
            else
                % User specified outcome of frequentist test (the builtin ttest), calculate BF from T and
                % df.
                statsForBf = p.Results.stats;
            end
            
            bf10 = bayesFactor.ttest('stats',statsForBf);
        end
        
        
        
        function [bf10,pValue,CI,stats] = ttest(X,varargin)
            % function [bf10,p,CI,stats] = ttest(X,Y,varargin)  - paired
            % function [bf10,p,CI,stats] = ttest(X,varargin)    - one sample
            % function [bf10,p,CI,stats] = ttest(X,M,varargin)   -one sample,non-zero mean
            %
            % Calculates Bayes Factor for a one-sample or paired T-test.
            %
            % X = single sample observations  (a column vector)
            % Y = paired observations (column vector) or a scalar mean to compare the samples in X to.
            %       {Defaults to 0]
            %
            % Optional Parm/Value pairs:
            % alpha - significance level for the frequentist test. [0.05]
            % tail - 'both','right', or 'left' for two or one-tailed tests [both]
            % scale - Scale of the Cauchy prior on the effect size  [sqrt(2)/2]
            % stats - A struct containing .tstat  , .df , .pvalue .tail and .N - This allows one to
            %               calculate BF10 directly from the results of a standard T-Test output.
            %
            % OUTPUT
            % bf10 - The Bayes Factor for the hypothesis that the mean is different
            %           from zero
            % p - p value of the frequentist hypothesis test
            % CI    - Confidence interval for the true mean of X
            % stats - Structure with .tstat, .df,
            %
            % BK - Nov 2018
            
            if isnumeric(X)
                if iseven(numel(varargin))
                    % Only X specified
                    Y = 0;
                    parms = varargin;
                else
                    % X and Y specified
                    if numel(varargin)>1
                        parms = varargin{2:end};
                    else
                        parms = {};
                    end
                    Y  =varargin{1};
                end
            else
                %Neither X nor Y specified (must be a call with 'stats' specified
                parms = cat(2,X,varargin);
                X=[];Y=[];
            end
            p=inputParser;
            p.addParameter('alpha',0.05);
            p.addParameter('tail','both',@(x) (ischar(x)&& ismember(upper(x),{'BOTH','RIGHT','LEFT'})));
            p.addParameter('scale',sqrt(2)/2);
            p.addParameter('stats',[],@isstruct);
            p.parse(parms{:});
            
            
            if isempty(p.Results.stats)
                % Calculate frequentist from the X and Y data
                tail = p.Results.tail;
                [~,pValue,CI,stats] = ttest(X,Y,'alpha',p.Results.alpha,'tail',tail);
                T = stats.tstat;
                df = stats.df;
                N = numel(X);
            else
                % User specified outcome of frequentist test (the builtin ttest), calculate BF from T and
                % df.
                T = p.Results.stats.tstat;
                df = p.Results.stats.df;
                pValue = p.Results.stats.p;
                tail  = p.Results.stats.tail;
                N = p.Results.stats.N;
                CI = [NaN NaN];
            end
            
            % Use the formula from Rouder 2009
            % This is the formula in that paper, but it does not use the
            % scale
            % numerator = (1+T.^2/(N-1)).^(-N/2);
            % fun  = @(g) ( ((1+N.*g).^-0.5) .* (1+T.^2./((1+N.*g).*(N-1))).^(-N/2) .* (2*pi).^(-1/2) .* g.^(-3/2).*exp(-1./(2*g))  );
            % This is with scale  (Checked against Morey's R package )
            r = p.Results.scale;
            numerator = (1+T.^2/df).^(-(df+1)/2);
            fun  = @(g) ( ((1+N.*g.*r.^2).^-0.5) .* (1+T.^2./((1+N.*g.*r.^2).*df)).^(-(df+1)/2) .* (2*pi).^(-1/2) .* g.^(-3/2).*exp(-1./(2*g))  );
            
            % Integrate over g
            bf01 = numerator/integral(fun,0,inf);
            % Return BF10
            bf10 = 1./bf01;
            
            switch (tail)
                case 'both'
                    % Nothing to do
                case {'left','right'}
                    % Adjust the BF using hte p-value as an estimate for the posterior
                    % (Morey & Wagenmakers, Stats and Prob Letts. 92 (2014):121-124.
                    bf10 = 2*(1-pValue)*bf10;
            end
        end
        
        function [bf10,p,pHat] = binotest(k,n,p)
            % Bayes factor for binomial test with k successes, n trials and base probability p.
            % INPUT
            %  k - number of successes
            %  n - number of draws
            %  p - true binomial probabiliy
            % OUTPUT
            % bf - Bayes Factor representing the evidence that this n/k
            % could result from random draws with p (BF>1) or not (BF<1)
            % p - p-value of a traditional test
            % pHat - esttimae of the binomial probablity
            
            % Code from Sam Schwarzkopf
            F = @(q,k,n,p) nchoosek(n,k) .* q.^k .* (1-q).^(n-k);
            bf01 = (nchoosek(n,k) .* p.^k .* (1-p).^(n-k)) / integral(@(q) F(q,k,n,p),0,1);
            bf10 = 1/bf01;
            
            if nargout>1
                % Traditional tests
                pHat = binofit(k,n,0.05);
                p = 1-binocdf(k,n,p);
            end
            
        end
        
        
        function [bf10,r,p] = corr(arg1,arg2)
            % Calculate the Bayes Factor for Pearson correlation between two
            % variables.
            % INPUT
            % (x,y)  - two vectors of equal length.
            % OR
            % (r,n)  - the correlation and number of samples
            %
            % OUTPUT
            % bf10 = the Bayes Factor for the hypothesis that r is differnt
            %           from zero (two-tailed).
            % r - the correlation
            % p - the tradiational p-value based on Fisher-transformed
            %
            if isscalar(arg1) && isscalar(arg2)
                r= arg1;
                n= arg2;
            else
                x=arg1;y=arg2;
                [r,p] = corr(x,y,'type','pearson');
                n=numel(x);
            end
            
            % Code from Sam Schwarzkopf
            F = @(g,r,n) exp(((n-2)./2).*log(1+g)+(-(n-1)./2).*log(1+(1-r.^2).*g)+(-3./2).*log(g)+-n./(2.*g));
            bf10 = sqrt((n/2)) / gamma(1/2) * integral(@(g) F(g,r,n),0,Inf);
            
            if nargout>1
                % Compute classical stats too
                t = r.*sqrt((n-2)./(1-r.^2));
                p = 2*tcdf(-abs(t),n-2);
            end
        end
        
        function allTerms = getAllTerms(lm)
            allTerms = lm.CoefficientNames;
            allTerms(strcmpi(allTerms,'(Intercept)')) = []; % Intercept not neeed
            % In the linearmixedmodel the factors have _1 appended in their
            % names. Even without grouping. I remove this here.
            allTerms = cellfun(@(x)(strrep(x,'_1','')),allTerms,'UniformOutput',false);
        end
        
        
        
    end
    
    %% Hide some of the handle class member functions for ease of use.
    methods (Hidden=true)
        
        function notify(~)
        end
        function addlistener(~)
        end
        function findobj(~)
        end
        function findprop(~)
        end
        function listener(~)
        end
    end
end