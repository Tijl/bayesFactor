% Utility script to publish the gettingStarted.m script as index.html on
% GitPages.
options = struct('format','html','outputDir','./docs/');
htmlDoc =publish('gettingStarted.m',options);
movefile(htmlDoc,'./docs/index.html')