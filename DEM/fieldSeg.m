%% File Dependencies: 
% Core: illiSeg.m, reconstruct3D.m
% Accessory: rgb2lab.m, tight_subplot.m, getAllFilesInFolder.m
%
% Flowchart: 
% Pair images into triplets, rename and compress the image files --- READ module
% 

%% Control panel
READ = false; COMPRESS = true; compress_size = 1024;
SEGMENT = true;
RECONSTRUCT = false;

% User define folder name here
inFolderName = './samples/test/'; 

%% READ: Read image files
if READ   
    % Create output folder for raw images
    rawFolderName = strcat(inFolderName, 'Raw/');
    if ~exist(rawFolderName, 'dir')
        mkdir(rawFolderName);
        
        % Specify the working folder and get all image files in it
        fnames = getAllFilesInFolder(inFolderName); % getAllFilesInFolder.m can be customed to filter out some file types
        if (mod(length(fnames),3) ~= 0) % check if the images are correctly taken 3 views of each particle
            error("Images are not paired in triplet...Please check if some views are missing!");
        end

        % Format arbitrary image file names to img000N_X and move to Raw folder
        % where N = image No. and X = 0(top)/1(front)/2(side) 
        % Note: raw images should be taken in sequence front-->side-->top!
        % The filename formatting should only be done once for a folder
        % Get the file extension
        [path, name, extension] = fileparts(fnames{1}); 
        for i = 1 : length(fnames)
            newFileName = strcat('img', sprintf('%04d', ceil(i / 3)), '_', num2str(mod(i, 3)), extension);

            % Rename files and put them under "Raw" folder
            movefile(fullfile(inFolderName, fnames{i}), fullfile(rawFolderName, newFileName));     
        end
    end
    
    % Avoid having too large image file and long running time, pre-processing the files
    if COMPRESS
        % Create output folder for compressed images
        compressFolderName = strcat(inFolderName, 'Compressed/');
        if ~exist(compressFolderName, 'dir')
            mkdir(compressFolderName);
        end
        
        fnames = getAllFilesInFolder(rawFolderName);
        for i = 1 : length(fnames)
            img = imread(fullfile(rawFolderName, fnames{i}));

            % Fix a default dimension of 1024
            [h,w,d] = size(img);
            if h > w
                img = imresize(img, [compress_size NaN]);
            else
                img = imresize(img, [NaN compress_size]);
            end

            % Save compressed image
            imwrite(img, fullfile(compressFolderName, fnames{i}));
        end
    end
    
end

%% SEGMENT: Particle and calibration ball segmentation
if SEGMENT
    close all;
    
    % Create output folder
    segFolderName = strcat(inFolderName, 'Segmentation/');
    if ~exist(segFolderName, 'dir')
        mkdir(segFolderName);
    end
    
    compressFolderName = strcat(inFolderName, 'Compressed/');
    fnames = getAllFilesInFolder(compressFolderName);
    
    summary = [];
    for object = 1 : length(fnames) / 3
        results = [];
        for i = 1 : 3 % image triplet of top-front-side views of an object
            views{i} = fullfile(compressFolderName, fnames{(object - 1) * 3 + i});
            results = cat(2, results, illiSeg(views{i}));
        end
        summary(2*(object-1)+1:2*(object-1)+2, :) = results;
        % summary compiles particle information of all the segmented images
        % Columns are the hole ratios of the rock particle and the
        % equivalent diameters of the calibration ball, interleaved following
        % top-front-side sequence. Rows are interleaved as rock-ball pair.
        % Example:
        % ratio1_top ratio1_front ratio1_side ---- rock1
        % diamt1_top diamt1_front diamt1_side ---- ball1
        % ratio2_top ratio2_front ratio2_side ---- rock2
        % diamt2_top diamt2_front diamt2_side ---- ball2
        % ratio3_top ratio3_front ratio3_side ---- rock3
        % diamt3_top diamt3_front diamt3_side ---- ball3
        % ...
    end
    % Save the summary info to disk
    save(fullfile(segFolderName, 'summary.mat'), 'summary');
end

%% RECONSTRUCT: 3D reconstruction and volume estimation
if RECONSTRUCT
    close all;

    % Create output folder
    segFolderName = strcat(inFolderName, 'Segmentation/');
    reconFolderName = strcat(inFolderName, 'Reconstruction/');
    if ~exist(reconFolderName, 'dir')
        mkdir(reconFolderName);
    end
    
    S = load(fullfile(segFolderName, 'summary.mat'), '-mat');
    info = S.summary;
    nums = size(info,1) / 2; % number of particles
    weights = [];
    volumes = [];
    % Calculate the benchmarked dimensions (x,y,z) from the least squares 
    % solution of the linear system
    for i = 1 : nums
        D = []; % diameters of calibration ball
        R = []; % hole ratios of rock
        for j = 1 : 3
            rocks{j} = imread(fullfile(segFolderName, strcat('timg', sprintf('%04d', i), '_', num2str(j - 1), '_rock.png')));
            balls{j} = imread(fullfile(segFolderName, strcat('timg', sprintf('%04d', i), '_', num2str(j - 1), '_ball.png')));
            D(j) = info(2 * i, j);
            %D(j) = min(size(balls{j}));
            R(j) = info(2 * i - 1, j);
        end
        rockVoxel = reconstruct3D(rocks, D);
        %holeRatio = 1 - mean(R);
        holeRatio = 1 / (5 * mean(R));
        %rockVoxel = rockVoxel * holeRatio;
        [ballVoxel, sphericity] = reconstruct3D(balls, D);
%         rockVolume = rockVoxel / (4 / 3 * 3.1415926 * (D(1)/2)^3) * 0.523599 * 16.3871;
        rockVolume =  0.8 * rockVoxel / ballVoxel * 8 * (2 - sqrt(2)) * 0.5^3 * 16.3871; % the orthogonal intersection volume of a sphere
        % rockVolume = rockVoxel / ballVoxel * 0.523599 * 16.3871; % calibration ball is V = 4/3 * PI * R3 = 0.523599 in3; 1 in3 = 16.3871 cm3
        rockWeight = rockVolume * 2.65; % typically rock density 2.65g/cm3
        volumes(i, 1) = rockVolume;
        weights(i, 1) = rockWeight;
        sphere(i,1) = sphericity;
        % Save the 3D voxel array to disk
        % save(fullfile(reconFolderName, 'volume.mhat'), 'volume');
        
    end
    
    % weights(:, 2) = [3175.15; 2487.7; 2463.9; 2955.1; 2235.8; 1712.5]; % old measure
    % weights(:, 2) = [3214.9; 2487.7; 2463.9; 2955.1; 2235.8; 1712.5]; % new measure
    % volumes(:, 2) = [1254.8; 916.4; 947.8; 1149.6; 871.7; 636.3]; % submerge measure
    % weights(:, 2) = [2235.8; 2235.8; 2235.8; 2235.8; 2235.8; 2235.8; 2487.7; 2487.7; 2487.7; 2487.7; 2487.7; 2487.7; 2955.1; 2955.1; 2955.1; 2955.1; 2955.1; 2955.1];
    volumes(:, 2) = [871.7; 871.7; 871.7; 871.7; 871.7; 871.7; 916.4;916.4; 916.4; 916.4; 916.4; 916.4; 1149.6; 1149.6; 1149.6; 1149.6;1149.6; 1149.6]; % May 30th
    %volumes(:, 2) = [636.3;636.3;636.3;636.3;636.3;636.3;947.8;947.8;947.8;947.8;947.8;947.8;1254.8;1254.8;1254.8;1254.8;1254.8;1254.8]; % June 6th
    error = (volumes(:,1) - volumes(:,2)) ./ volumes(:,2) * 100; % percentage
    % error = (weights(:,1) - weights(:,2)) ./ weights(:,2) * 100;
    figure; hold on;
    % plot(weights(:,2), weights(:,1), '*r'), xlim([0 4000]), ylim([0 4000]);
    plot(volumes(:,2), volumes(:,1), '*r'), xlim([0 2000]), ylim([0 2000]);
    text(volumes(:,2), volumes(:,1)- 500, num2str([1:18]'));
    % average
%     plot(volumes(1,2), mean(volumes(1:6,1)), 'ob');
%     plot(volumes(7,2), mean(volumes(7:12,1)), 'ob');
%     plot(volumes(13,2), mean(volumes(13:18,1)), 'ob');
    xlabel('Actual Volume (in cm3)'), ylabel('Reconstructed Volume (in cm3)');
    rangeLine = 0:500:2000;
    plot(rangeLine, rangeLine, '-k', 'LineWidth', 1);
    percent10Error = rangeLine .* 0.1;
    percent20Error = rangeLine .* 0.2;
    plot(rangeLine, rangeLine + percent10Error, '--b', 'LineWidth', 1);
    plot(rangeLine, rangeLine + percent20Error, '--g', 'LineWidth', 1);
    plot(rangeLine, rangeLine - percent10Error, '--b', 'LineWidth', 1);
    plot(rangeLine, rangeLine - percent20Error, '--g', 'LineWidth', 1);
    legend('Data points', 'Reference Line', '10% Eror', '20% Error', 'Location', 'NorthWest');
    saveas(gcf, './plot1.png');
    
end

%% Notes
% Volume visualization tutorial:
% https://blogs.mathworks.com/videos/2009/10/23/basics-volume-visualization-19-defining-scalar-and-vector-fields/
% https://stackoverflow.com/questions/2942251/matlab-3d-volume-visualization-and-3d-overlay
% https://stackoverflow.com/questions/13553108/how-i-can-display-3d-logical-volume-data-matlab
% https://stackoverflow.com/questions/6891154/creating-3d-volume-from-2d-slice-set-of-grayscale-images
% 
% Isosurface: isosurface(V, value)
% https://www.mathworks.com/help/matlab/ref/isosurface.html
% 
% 3D binary boundary of mask:
% https://www.mathworks.com/matlabcentral/answers/85180-multi-dimensional-version-of-bwboundaries
%
% 3D boundary of a set of points: boundary(x,y,z)
% https://www.mathworks.com/help/matlab/ref/boundary.html
%
% 3D Minkowski geometric measures: imMinkowski package
% https://www.mathworks.com/matlabcentral/fileexchange/33690-geometric-measures-in-2d-3d-images
%
% 3D voxel rendering: vol3d package
% https://www.mathworks.com/matlabcentral/fileexchange/22940-vol3d-v2
% https://blogs.mathworks.com/pick/2013/10/04/easy-visualization-of-volumetric-data/
% 
% 3D reconstruct:
% https://www.mathworks.com/matlabcentral/fileexchange/3280-voxel
% https://www.mathworks.com/matlabcentral/fileexchange/42876-surf2solid-make-a-solid-volume-from-a-surface-for-3d-printing?focused=3810976&tab=function
% https://www.mathworks.com/matlabcentral/fileexchange/24484-geom3d?focused=8549167&tab=function
% https://www.mathworks.com/matlabcentral/fileexchange/37268-3d-volume-visualization
% https://www.mathworks.com/matlabcentral/fileexchange/59161-volumetric-3?s_tid=srchtitle
% https://www.mathworks.com/help/images/explore-3-d-volumetric-data-with-volume-viewer-app.html