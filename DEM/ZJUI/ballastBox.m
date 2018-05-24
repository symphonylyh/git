%% Control panel
clc;
close all;

READ = true; % read raw file and pre-cache target data
PLOT = false; % plot based on pre-cached data

%% Set I/O folder
% Usage: Put the input files in a user-defined folder under './Input', and
% run this ballastBox.m code
folderName = 'ZJUI_252km'; % user-define
inFolderName = strcat('./Input/', folderName); 
outFolderName = strcat('./Output/', folderName);
if ~exist(outFolderName, 'dir')
	mkdir(outFolderName);
end

%% Read file
if READ
% DEM output was splitted into multiple files. We need to glue them
% together and plot the time history
fnames = getAllFilesInFolder(inFolderName);
vibrations = {}; % initialize as global variable
steps = 0; % record the past time steps
for f = 1 : length(fnames)    
file = fopen(fullfile(inFolderName, fnames{f}));
% File format:
% 1st line (notation): Velocity[3] | Rotational_velocity[3] | centroid[3] | #of contacts | (Force[3] contactPoints[3]) tuple of each contact
% 2nd line (particle ID): @ ID
% 3rd line (1st line data for each time step)
% ...
% nth line (next particle ID): @ ID
% n+1th line (data for this particle)
% ...

% Bootstrap file reading
header = fgetl(file); % ignore 1st line (header)
% header = fgetl(file); % 2nd line
i = 1; % i: particle index
j = steps + 1; % j: time step index
data = textscan(header, '%c %d');
ID(i) = data{2};
i = i + 1;

timeStep = 1.61795e-4;

%% Read file
while feof(file) ~= 1  
    
    line = fgetl(file);
    if strncmp(line, '@', 1) % ID line
        data = textscan(line, '%c %d');
        ID(i) = data{2};
        if i - 1 > length(vibrations) % first-time assign
            vibrations{i - 1} = velocityZ; % push the recorded data for last particle ID
        else
            vibrations{i - 1} = cat(2, vibrations{i - 1}, velocityZ);
        end
        i = i + 1;
        j = 1; % restart time step
    else % Data line
        data = textscan(line, '%f %f %f %*[^\n]', 'Delimiter', ' ');  % %*[^\n] means skip the rest
        velocityZ(j) = data{3};
        j = j + 1;
    end
 
end 
fclose(file);

vibrations{i - 1} = velocityZ; % fill the last loop
steps = j - 1; % record total number of time steps

end % end file loop
save(fullfile(outFolderName, 'data.mat'), 'vibrations');
end % end READ switch

fileName = 'd11_0.bx';
file = fopen(fileName);

%% Plot data
if PLOT
S = load(fullfile(outFolderName, 'data.mat'), '-mat');
info = S.vibrations;
% X axis (time axis)
for i = 1 : steps
    time(i) = timeStep * i;
end

% Y axis (vertical vibration velocity)
% Plot for all particles in the box
for i = 1 : length(vibrations)
    plot(time, vibrations{i}, '-r');
    hold on;
    xlabel('Time (s)', 'FontWeight', 'Bold'), ylabel('Vertical Vibration Velocity (mm/s)', 'FontWeight', 'Bold');
    print(strcat('vz_', num2str(ID(i)), '.png'), '-r200', '-dpng');
    close all;
end

end % end PLOT switch