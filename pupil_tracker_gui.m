function varargout = pupil_tracker_gui(varargin)
    % PUPIL_TRACKER_GUI MATLAB code for pupil_tracker_gui.fig
    %      PUPIL_TRACKER_GUI, by itself, creates a new PUPIL_TRACKER_GUI or raises the existing
    %      singleton*.
    %
    %      H = PUPIL_TRACKER_GUI returns the handle to a new PUPIL_TRACKER_GUI or the handle to
    %      the existing singleton*.
    %
    %      PUPIL_TRACKER_GUI('CALLBACK',hObject,eventData,handles,...) calls the local
    %      function named CALLBACK in PUPIL_TRACKER_GUI.M with the given input arguments.
    %
    %      PUPIL_TRACKER_GUI('Property','Value',...) creates a new PUPIL_TRACKER_GUI or raises the
    %      existing singleton*.  Starting from the left, property value pairs are
    %      applied to the GUI before pupil_tracker_gui_OpeningFcn gets called.  An
    %      unrecognized property name or invalid value makes property application
    %      stop.  All inputs are passed to pupil_tracker_gui_OpeningFcn via varargin.
    %
    %      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
    %      instance to run (singleton)".
    %
    % See also: GUIDE, GUIDATA, GUIHANDLES
    
    % Edit the above text to modify the response to help pupil_tracker_gui
    
    % Last Modified by GUIDE v2.5 19-Mar-2019 10:33:22
    
    % Begin initialization code - DO NOT EDIT
    gui_Singleton = 1;
    gui_State = struct('gui_Name',       mfilename, ...
        'gui_Singleton',  gui_Singleton, ...
        'gui_OpeningFcn', @pupil_tracker_gui_OpeningFcn, ...
        'gui_OutputFcn',  @pupil_tracker_gui_OutputFcn, ...
        'gui_LayoutFcn',  [] , ...
        'gui_Callback',   []);
    if nargin && ischar(varargin{1})
        gui_State.gui_Callback = str2func(varargin{1});
    end
    
    if nargout
        [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
    else
        gui_mainfcn(gui_State, varargin{:});
    end
    % End initialization code - DO NOT EDIT
    
    
    % --- Executes just before pupil_tracker_gui is made visible.
function pupil_tracker_gui_OpeningFcn(hObject, eventdata, handles, varargin)
    handles.output = hObject;
    % my additions
    handles.video_filename='Z:\Polack\voltage_sensitive_dye\pupilReflex\mouse008 (1i)\monoeyemouse_001_no_lidocaine_2sBlack2sBlue_maxSat.mj2';
    handles.video_filename='G:\monoeyemouse_001_no_lidocaine_2sBlack2sBlue_maxSat.mj2';
    handles.vid_obj=VideoReader(handles.video_filename);
    handles.roi.Prior_Amp=struct('Value',0.5,'Min',0,'Max',1,'strformat','%.2f');
    handles.roi.Prior_Sigma_Factor=struct('Value',0.5,'Min',1/5,'Max',5,'strformat','%.2f');
    handles.convolve.Disk_Radius=struct('Value',1,'Min',0.5,'Max',20,'strformat','%.2f');
    handles.threshold.Threshold=struct('Value',0.9,'Min',0,'Max',1,'strformat','%.2f');
    handles.threshold.Min_Area=struct('Value',30,'Min',1,'Max',100,'strformat','%d');
    handles.threshold.Transparency=struct('Value',0.5,'Min',0,'Max',1,'strformat','%.2f');
    handles.last_view=[]; % to keep track of changes of viewmode so slider can get updated to current processing step
    % Update handles structure
    guidata(hObject, handles);
    % UIWAIT makes pupil_tracker_gui wait for user response (see UIRESUME)
    uiwait(handles.figure1);
    
    % --- Executes when user attempts to close figure1.
function figure1_CloseRequestFcn(hObject, eventdata, handles)
    handles.view_play_video.Text='Play Video'; % signal end of video loop
    pause(1/4); % wait for last frame to finish
    delete(handles.figure1);
    
    
function loop_video(handles)
    if isempty(handles.vid_obj) || ~isvalid(handles.vid_obj)
        error('should not be able to get here');
    end
    % clear all persistent variables in subfunctions
    do_crop;
    do_roi;
    % to be able to control the video with the progress slider, the slider
    % update is the master and the video progress is the slave, otherwise
    % the slider gets updates while user tries to move it
    %nr_frames = round(handles.vid_obj.Duration*handles.vid_obj.FrameRate);
    handles.video_progress_slider.Max=handles.vid_obj.Duration;
    handles.video_progress_slider.Min=0;
    handles.video_progress_slider.Value=0;
    frame_duration=1/handles.vid_obj.FrameRate;
    while isvalid(handles.view_play_video) && strcmpi(handles.view_play_video.Text,'Pause Video')
        try
            handles.vid_obj.CurrentTime=handles.video_progress_slider.Value;
        catch me
            warning(me.message);
            handles.vid_obj.CurrentTime=0;
        end
        
        if handles.vid_obj.hasFrame
            fr=handles.vid_obj.readFrame;
            fr=fr(:,:,1); % only red channel
            fr=double(fr)/255;
            [handles,fr]=do_crop(handles,fr);
            cropped_fr=fr; % keep a copy to overlay result on later
            [handles,fr,prior_x,prior_y]=do_roi(handles,fr);
            [handles,fr]=do_convolve(handles,fr);
            [handles,fr]=do_threshold(handles,fr,cropped_fr,prior_x,prior_y);
            %  show_final(fr,cropped_fr);
        end
        
        handles.video_progress_slider.Value=handles.video_progress_slider.Value+frame_duration;
        if handles.video_progress_slider.Value>=handles.video_progress_slider.Max
            handles.video_progress_slider.Value=0;
        end
        drawnow limitrate
    end
    
function [handles,fr]=do_crop(handles,fr)
    persistent crop_box imrect_obj
    if nargin==0
        [crop_box,imrect_obj]=deal([]);
        return
    end
    if isempty(crop_box)
        crop_box=[1 1 size(fr,2)-1 size(fr,1)-1];
    end
    fr=clamp(fr,0,1);
    if strcmpi(get_active_view(handles),'crop')
        if ~strcmpi(handles.last_view,'crop')
            % here be what need to be done once after switching to this view
            handles.last_view='crop';
            handles.slider1.Visible='off';
            handles.slider2.Visible='off';
            handles.slider3.Visible='off';
            handles.slider4.Visible='off';
        end
        delete(findobj(handles.axes1.Children,'Tag','imellipse'));
        colormap(handles.axes1,'gray');
        axlims=[handles.axes1.YLim(2)-handles.axes1.YLim(1) handles.axes1.XLim(2)-handles.axes1.XLim(1)];
        if ~all(axlims==size(fr))
            imagesc(handles.axes1,fr);
            colormap(handles.axes1,'gray');
        else
            set(findobj(handles.axes1.Children,'Type','image'),'CData',fr);
        end
        if isempty(imrect_obj) || ~isvalid(imrect_obj)
            imrect_obj=imrect(handles.axes1,crop_box);%,'Tag','crop_rect');
        else
            crop_box=imrect_obj.getPosition;
            crop_box=round(crop_box);
            if crop_box(1)<1
                crop_box(1)=1;
            end
            if crop_box(2)<1
                crop_box(2)=1;
            end
            if crop_box(1)+crop_box(3)>size(fr,2)
                crop_box(3)=size(fr,2)-crop_box(1);
            end
            if crop_box(2)+crop_box(4)>size(fr,1)
                crop_box(4)=size(fr,1)-crop_box(2);
            end
            % imrect_obj.setPosition=crop_box;
        end
        drawnow limitrate
    end
    fr=fr(crop_box(2):crop_box(2)+crop_box(4),crop_box(1):crop_box(1)+crop_box(3));
    
function [handles,fr,Xmu,Ymu]=do_roi(handles,fr)
    persistent roi_box imellipse_obj
    if nargin==0
        [roi_box,imellipse_obj]=deal([]);
        return
    end
    if isempty(roi_box)
        roi_box=[1 1 size(fr,2)-1 size(fr,1)-1];
    end
    if isempty(imellipse_obj) || ~isvalid(imellipse_obj)
        imellipse_obj=imellipse(handles.axes1,roi_box);
    end
    
    verts=imellipse_obj.getVertices;
    if ~strcmpi(get_active_view(handles),'roi')
        delete(imellipse_obj)
    end
    [xx,yy]=meshgrid(1:size(fr,2),1:size(fr,1));
    hardmask=~inpolygon(xx,yy,verts(:,1),verts(:,2));
    Xmu=mean(verts(:,1));
    Xsig=range(verts(:,1))*handles.roi.Prior_Sigma_Factor.Value;
    Ymu=mean(verts(:,2));
    Ysig=range(verts(:,2))*handles.roi.Prior_Sigma_Factor.Value;
    prior=normpdf(xx,Xmu,Xsig) .* normpdf(yy,Ymu,Ysig);
    prior=clamp(-prior,handles.roi.Prior_Amp.Value,1);
    fr=fr.*prior;
    fr=clamp(fr,0,1);
    fr(hardmask)=nan;
    if strcmpi(get_active_view(handles),'roi')
        if ~strcmpi(handles.last_view,'roi')
            handles.last_view='roi';
            % here be what need to be done once after switching to this view
            handles=appropriate_slider(handles,'slider1','roi','Prior_Amp');
            handles=appropriate_slider(handles,'slider2','roi','Prior_Sigma_Factor');
            handles.slider3.Visible='off';
            handles.slider4.Visible='off';
        end
        handles.roi.Prior_Amp.Value=handles.slider1.Value;
        handles.roi.Prior_Sigma_Factor.Value=handles.slider2.Value;
        delete(findobj(handles.axes1.Children,'Tag','imrect'));
        colormap(handles.axes1,'gray');
        axlims=[handles.axes1.YLim(2)-handles.axes1.YLim(1) handles.axes1.XLim(2)-handles.axes1.XLim(1)];
        if ~all(axlims==size(fr))
            imagesc(handles.axes1,fr);
            colormap(handles.axes1,'parula');
        else
            set(findobj(handles.axes1.Children,'Type','image'),'CData',fr);
        end
        try
            roi_box=imellipse_obj.getPosition; % roi_box will be used to rebuild the ellipse when the view is set to another step
        catch me
            % if view is switched while in the middle of a step it's
            % possble imellipse_obj is deleted will be fine next frame...
            % event based control in matlab is problematic will look into a
            % real solution
        end
            
        drawnow limitrate
    end
    
function [handles,fr]=do_convolve(handles,fr)
    fr=clamp(fr,0,1);
    disk=fspecial('disk',handles.convolve.Disk_Radius.Value);
    fr=conv2(fr,disk,'same'); % must be same
    %  fr=fr.^2;
    fr=clamp(-fr,0,1);
    if strcmpi(get_active_view(handles),'convolve')
        if ~strcmpi(handles.last_view,'convolve')
            handles.last_view='convolve';
            % here be what need to be done once after switching to this view
            handles=appropriate_slider(handles,'slider1','convolve','Disk_Radius');
            handles.slider2.Visible='off';
            handles.slider3.Visible='off';
            handles.slider4.Visible='off';
        end
        handles.convolve.Disk_Radius.Value=handles.slider1.Value;
        delete(findobj(handles.axes1.Children,'Tag','imrect'));
        delete(findobj(handles.axes1.Children,'Tag','imellipse'));
        colormap(handles.axes1,'parula');
        axlims=[handles.axes1.YLim(2)-handles.axes1.YLim(1) handles.axes1.XLim(2)-handles.axes1.XLim(1)];
        if ~all(axlims==size(fr))
            imagesc(handles.axes1,fr);
            colormap(handles.axes1,'parula');
        else
            set(findobj(handles.axes1.Children,'Type','image'),'CData',fr);
        end
        drawnow limitrate
    end
    
    
function [handles,fr]=do_threshold(handles,fr,cropped_fr,prior_x,prior_y)
    fr=clamp(fr,0,1);
    fr=imbinarize(fr,handles.threshold.Threshold.Value);
    % fr=bwmorph(fr,'close');
    % fr=bwmorph(fr,'open');
    fr=bwareaopen(fr,floor(handles.threshold.Min_Area.Value));
    %  fr=imfill(fr,'holes');
    [bnds,labelmap,n_objects]=bwboundaries(fr);
    if n_objects>1
        % find the object that's closest to the prior center
        min_dist=Inf;
        for i=1:n_objects
            dist=hypot(mean(bnds{i}(:,2))-prior_x,mean(bnds{i}(:,1))-prior_y);
            if dist<min_dist
                min_dist=dist;
                nearest_to_prior=i;
            end
        end
        labelmap=labelmap==nearest_to_prior;
    end
    labelmap = bwconvhull(labelmap);
    [R,G,B]=deal(cropped_fr);
    G(labelmap==1)=min(1,G(labelmap==1)+handles.threshold.Transparency.Value);
    fr=cat(3,R,G,B);
    if strcmpi(get_active_view(handles),'threshold')
        if ~strcmpi(handles.last_view,'threshold')
            handles.last_view='threshold';
            % here be what need to be done once after switching to this view
            handles=appropriate_slider(handles,'slider1','threshold','Threshold');
            handles=appropriate_slider(handles,'slider2','threshold','Min_Area');
            handles=appropriate_slider(handles,'slider3','threshold','Transparency');
            handles.slider4.Visible='off';
        end
        handles.threshold.Threshold.Value=handles.slider1.Value;
        handles.threshold.Min_Area.Value=handles.slider2.Value;
        handles.threshold.Transparency.Value=handles.slider3.Value;
        delete(findobj(handles.axes1.Children,'Tag','imrect'));
        delete(findobj(handles.axes1.Children,'Tag','imellipse'));
        colormap(handles.axes1,'parula');
        axlims=[handles.axes1.YLim(2)-handles.axes1.YLim(1) handles.axes1.XLim(2)-handles.axes1.XLim(1)];
        if ~all(axlims==size(R))
            imagesc(handles.axes1,fr);
            colormap(handles.axes1,'parula');
        else
            set(findobj(handles.axes1.Children,'Type','image'),'CData',fr);
        end
        drawnow limitrate
    end
    
function varargout = pupil_tracker_gui_OutputFcn(hObject, eventdata, handles)
    varargout{1} = [];
    
function video_progress_slider_Callback(hObject, eventdata, handles)
    
function slider_Callback(hObject, eventdata, handles)
    % update the tooltipstr
    if isempty(hObject.TooltipString) || ~any(hObject.TooltipString=='(')
        return
    end
    open=find(hObject.TooltipString=='(',1,'first');
    hObject.TooltipString(open:end)=[]; % remove previous value
    hObject.TooltipString=[hObject.TooltipString '(' sprintf(hObject.UserData,hObject.Value) ')'];
        
    
    
    % --------------------------------------------------------------------
function file_menu_Callback(hObject, eventdata, handles)

% --------------------------------------------------------------------
function view_menu_Callback(hObject, eventdata, handles)
    
    
function view_mitem_Callback(hObject, eventdata, handles)
    % Call back shared by all step view menu item callbacks
    [~,selected_view_item]=get_active_view(handles);
    selected_view_item.Checked='off';
    hObject.Checked='on';
    
function [view_str,selected_view_item]=get_active_view(handles)
    [view_str,selected_view_item]=deal('');
    view_items=findobj(handles.figure1,'Tag','view_menu');
    checked_item = findobj(view_items,'Checked','on');
    if numel(checked_item)>1
        error('supposed to be only 1 checked item');
    end
    view_str=checked_item.Label;
    selected_view_item=checked_item;
    
    
    
function open_video_mitem_Callback(hObject, eventdata, handles)
    if strcmpi(handles.view_play_video.Text,'Pause Video')
        handles.view_play_video.Text='Play Video'; % signal video to stop
        pause(0.2); % wait for last frame to finish...
        delete(handles.vid_obj);
    end
    [fname,folder]= uigetfile({'*.avi;*.mj2;*.mp4;','All Video Files (*.avi, *.mj2, *.mp4)'; ...
        '*.*', 'All Files (*.*)'},'Pick a Video File');
    handles.video_filename=fullfile(folder,fname);
    if isnumeric(handles.video_filename)
        return; % user canceled file selection
    end
    try
        handles.vid_obj=VideoReader(handles.video_filename);
        [~,nm,ext]=fileparts(handles.video_filename);
        handles.figure1.Name=[mfilename ' - ' nm ext];
    catch me
        handles.figure1.Name=mfilename;
        handles.vid_obj=[];
        uiwait(errordlg(me.message,mfilename,'modal'));
        return
    end
    
    
function export_pupil_data_mitem_Callback(hObject, eventdata, handles)
    
    
    
function quit_mitem_Callback(hObject, eventdata, handles)
    figure1_CloseRequestFcn(hObject, eventdata, handles)
    
    
function view_play_video_Callback(hObject, eventdata, handles)
    %hObject=toggle_check(hObject);
    if strcmpi(handles.view_play_video.Text,'Play Video')
        if isempty(handles.vid_obj) || ~isvalid(handles.vid_obj)
            msg={'No video file openened'};
            uiwait(errordlg(msg,mfilename,'modal'));
        end
        handles.view_play_video.Text='Pause Video';
        loop_video(handles);
    elseif strcmpi(handles.view_play_video.Text,'Pause Video')
        handles.view_play_video.Text='Play Video';
    else
        error('unknown play/pause button label');
    end
    
    
    
function hObject=toggle_check(hObject)
    if strcmpi(hObject.Checked,'on')
        hObject.Checked='off';
    else
        hObject.Checked='on';
    end
    
function x=clamp(x,mini,maxi)
    if mini>maxi
        error('minimum exceeds maximum');
    end
    x=x-min(x(:));
    x=x./max(x(:));
    x=x*(maxi-mini);
    x=x+mini;
    
    
function handles=appropriate_slider(handles,slidername,viewstep,prop)
    % slidername eg 'slider1' ;  viewstep eg 'roi'; prop eg 'Prior_Amp'
    handles.(slidername).Visible='on';
    handles.(slidername).Min=handles.(viewstep).(prop).Min;
    handles.(slidername).Max=handles.(viewstep).(prop).Max;
    handles.(slidername).Value=handles.(viewstep).(prop).Value;
    handles.(slidername).UserData=handles.(viewstep).(prop).strformat;
    prop=strrep(prop,'_',' ');
    fmt=handles.(slidername).UserData; % e.g. %.2f
    handles.(slidername).TooltipString=[prop ' (' sprintf(fmt,handles.(slidername).Value) ')'];
    
