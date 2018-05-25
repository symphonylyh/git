% File Dependencies: rgb2lab.m, tight_subplot.m, getAllFilesInFolder.m

%% Control panel
SEGMENT = false;
RESIZE = true;

%% Read image folder
% Specify the working folder and get all image files in it
inFolderName = './samples/Apr_25_2018/'; % user-define
fnames = getAllFilesInFolder(inFolderName); % this function is tuned to ignore any additional folder such as "Segmentation" and "Resizing"
if (mod(length(fnames),3) ~= 0)
    error("Images are not paired in triplet...Abort!");
end

% Format arbitrary image file names to img000N_X 
% where N = image No. and X = 0(top)/1(front)/2(side) 
% Note: the sequence of raw images should be taken in front-->side-->top!
% The filename formatting should only be done once for a folder
if fnames{1}(1:3) ~= 'img' % if already formatted, skip
    % Get the file extension
    [path, name, extension] = fileparts(fnames{1}); 
    for i = 1 : length(fnames)
        % Rename file
        movefile(fullfile(inFolderName, fnames{i}), fullfile(inFolderName, strcat('img', sprintf('%04d', ceil(i / 3)), '_', num2str(mod(i, 3)), extension)));
    end
    % Update the recorded file name if they are renamed
    fnames = getAllFilesInFolder(inFolderName);
end

% Create output folder
outFolderName = strcat(inFolderName, 'Segmentation/');
if ~exist(outFolderName, 'dir')
	mkdir(outFolderName);
end


%% Segmentatioin
if SEGMENT
    %img = illiSeg(fullfile(inFolderName,fnames{21})); % single image
    summary = [];
    for object = 1 : length(fnames) / 3
        results = [];
        for i = 1 : 3 % image triplet of top-front-side views of an object
            views{i} = fullfile(inFolderName, fnames{(object - 1) * 3 + i});
            results = cat(2, results, illiSeg(views{i}));
        end
        summary(2*(object-1)+1:2*(object-1)+2, :) = results;
        % summary compiles particle information of all the segmented images
        % Columns are the bounding box dimensions of the rock particle
        % expressed in x-y/width-height, three views stacked following the
        % top-front-side sequence:
        % width0(x) height0(y) width1(x) height1(y) width2(x) height2(y) 
        % Rows are interleaved as rock-ball pair for one set of photos:
        % set1_rock
        % set1_ball
        % set2_rock
        % set2_ball
        % ...
    end
    % Save the summary info to disk
    save(fullfile(outFolderName, 'summary.mat'), 'summary');
end

%% 3D volume estimation
if RESIZE
    S = load(fullfile(outFolderName, 'summary.mat'), '-mat');
    info = S.summary;
    nums = size(info,1) / 2; % number of particle sets
    
    % Calculate the benchmarked dimensions (x,y,z) from the least squares 
    % solution of the linear system
    for i = 5 % 1:6
        for j = 1 : 3
            views{j} = imread(fullfile(inFolderName, 'Segmentation/', strcat('timg', sprintf('%04d', i), '_', num2str(j - 1), '_rock.png')));
            D(j) = info(2 * i, 2 * j - 1);
        end
        % Normalize with respect to the top view based on the size of
        % calibration ball
        views{2} = imresize(views{2}, D(1) / D(2));
        views{3} = imresize(views{3}, D(1) / D(3));
        info(2 * i - 1, 2 * 2 -1 : 2 * 2) = [size(views{2}, 2) size(views{2}, 1)];
        info(2 * i - 1, 2 * 3 -1 : 2 * 3) = [size(views{3}, 2) size(views{3}, 1)];
        
        % Following the sequence of photos top-front-side
        % a right-hand coordinates system is used:
        % --------> x
        % |
        % |
        % |
        % |
        % _
        % y
        % and positive z is pointing into the screen
        % in the image sets taken April 25th, each row in summary matrix
        % is [z x x y z y]
        % so A matrix can be formed
        b = info(2 * i - 1, :)';
        A = [0 0 1; 1 0 0; 1 0 0; 0 1 0; 0 0 1; 0 1 0];
        scale = ceil(A \ b); % [x y z]
        top = imresize(views{1}, [scale(1) scale(3)]);
        front = imresize(views{2}, [scale(2) scale(1)]);
        side = imresize(views{3}, [scale(2) scale(3)]);
        
        % Extrude and rearrange into [x y z] dimension
        top_extrude = repmat(top, [1 1 scale(2)]); % [x z y]
        top_extrude = permute(top_extrude, [1 3 2]);
        front_extrude = repmat(front, [1 1 scale(3)]); % [y x z]
        front_extrude = permute(front_extrude, [2 1 3]);
        side_extrude = repmat(side, [1 1 scale(1)]); % [y z x]
        side_extrude = permute(side_extrude, [3 1 2]);
        
        % Intersect the three extruded body
        volume = top_extrude & front_extrude & side_extrude;
        volume = permute(volume, [1 2 3]);
%         [Rx Ry Rz] = size(volume); % the reconstruct coordinates system used above
%         [Vx Vy Vz] = meshgrid(1:Rz, 1:Rx, 1:Ry); % rearrange the axis to Matlab plot's right-handed system
%         v = double(volume);
%         p = patch( isosurface(v,0) );                 %# create isosurface patch
%         isonormals(v, p)                              %# compute and set normals
%         set(p, 'FaceColor','r', 'EdgeColor','none')   %# set surface props
%         daspect([1 1 1])                              %# axes aspect ratio
%         view(3), axis vis3d tight, box on, grid on    %# set axes props
%         camproj perspective                           %# use perspective projection
%         camlight, lighting phong, alpha(1)  
%         
%         surfaceVoxels = volume - imerode(volume, true(3));
%         
%         vol3d('cdata',volume,'texture','3D');
%         view(45,15);  axis tight;axis off;
%         camlight; camlight(-90,-10); camlight(180,-10);lighting phong;
%         alphamap('rampup');
%         alphamap(0.05 .* alphamap);
%         figure;
%         cmap = [0 0 1];
%         hpat = PATCH_3Darray(volume, cmap);
        
        voxel = sum(volume(:));
        rockVolume = voxel / D(1)^3 * 1^3; % in in^3
        rockWeight = rockVolume * 16.3871 * 2.65; % 1 in3 = 16.3871 cm3; typically rock density 2.65g/cm3
        volumes(i, 1) = rockVolume * 16.3871;
        weights(i, 1) = rockWeight;
        % Save the 3D voxel array to disk
        % save(fullfile(outFolderName, 'volume.mat'), 'volume');
        
    end
    
    weights(:, 2) = [3175.15; 2487.7; 2463.9; 2955.1; 2235.8; 1712.5]; % old measure
    weights(:, 2) = [3214.9; 2487.7; 2463.9; 2955.1; 2235.8; 1712.5]; % new measure
    volumes(:, 2) = [1254.8; 916.4; 947.8; 1149.6; 871.7; 636.3]; % submerge measure
    figure;
    %plot(weights(:,2), weights(:,1), '*r'), xlim([1000 4000]), ylim([1000 4000]), refline(1, 0);
    plot(volumes(:,2), volumes(:,1), '*r'), xlim([500 1500]), ylim([500 1500]), refline(1, 0);
    % Create output folder for the resized particle image
    outFolderName = strcat(inFolderName, 'Resizing/');
    if ~exist(outFolderName, 'dir')
        mkdir(outFolderName);
    end
    
    
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