unit UIDialog;

interface

uses
  Winapi.Windows, Winapi.Messages, System.Types, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls, PhotonFile, Vcl.Grids, Vcl.ValEdit, Misc, StrClasses, DateTimeTools,
  Vcl.ComCtrls, Math;

type
  TMainForm = class(TForm)
    layerOut: TImage;
    uiOpenDialog: TOpenDialog;
    btnOpenFile: TButton;
     vleGlobals: TValueListEditor;
    sbLayerSelect: TScrollBar;
    btnProcessLayers: TButton;
    lbInfo: TLabel;
    pbStatus: TProgressBar;
    btnSaveFile: TButton;
    uiSaveDialog: TSaveDialog;
    cbxAddLayers: TCheckBox;
    cbxShowPreview0: TCheckBox;
    cbxShowPreview1: TCheckBox;
    btnSelectScript: TButton;
    btnLoadImage: TButton;
    cbxInverseImage: TCheckBox;
    procedure btnOpenFileClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormResize(Sender: TObject);
    procedure sbLayerSelectScroll(Sender: TObject; ScrollCode: TScrollCode; var ScrollPos: Integer);
    procedure btnProcessLayersClick(Sender: TObject);
    procedure btnSaveFileClick(Sender: TObject);
    procedure cbxShowPreview0Click(Sender: TObject);
    procedure cbxShowPreview1Click(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure btnSelectScriptClick(Sender: TObject);
    procedure vleGlobalsStringsChange(Sender: TObject);
    procedure btnLoadImageClick(Sender: TObject);
  private
    { Private declarations }
       phFile: TPhotonFile;
        lproc: TLayerProcessor; // for frame display
      lp_pool: array of TLayerProcessor;

     preview0: TBitmap;
     preview1: TBitmap;
    orig_proc: TWndMethod;
    open_mode: Boolean;

    procedure SetDefValue(const key: String; val: Integer); overload;
    procedure ShowPreview (index: Integer);
    procedure PatchWindowProc(var Message: TMessage);
    function  GetLayerProcessor: TLayerProcessor;
    procedure WaitThreads(timeOut: DWORD);
    procedure ProducePhotonFile;
    function GetIntGlobal(const key: String): Integer;
    function GetFloatGlobal(const key: String): Single;
    procedure SetFloatGlobal(const key: String; const Value: Single);
  public
    { Public declarations }

    property  IntGlobals[const key: String]: Integer  read GetIntGlobal;
    property  FloatGlobals[const key: String]: Single read GetFloatGlobal write SetFloatGlobal;


    procedure RedrawLayer;
  end;

var
  MainForm: TMainForm;

implementation
uses Contnrs;

{$R *.dfm}


// fit big rect [sw x sh] into small rect [tw x th]
function ScaleFit(tw, th, sw, sh: Integer): TRect;
var
   art: Single;
   ars: Single;

begin
 art := tw / th;
 ars := sw / sh;   // need lock this aspect ratio
 result.SetLocation (0, 0);
 if ars > art then // 0.5 > 0.4
  begin
   result.Width := Round (th / ars);
   result.Height := th;
   if result.Width > tw then
    begin
     result.Width := tw;
     result.Height := Round (tw * ars);
     result.SetLocation ( 0, (th - result.Height) div 2 );
    end
   else
    result.SetLocation ( (tw - result.Width) div 2, 0 );
  end
 else
  begin           // 0.5 < 1.5
   result.Width := tw;
   result.Height := Round (tw / ars);
   if result.height > th then
     begin
      result.Width := Round(th * ars);
      result.Height := th;
      result.SetLocation ( (tw - result.Width) div 2, 0 );
     end
      else
     result.SetLocation ( 0, (th - result.Height) div 2 );
  end;
end;


function TMainForm.GetFloatGlobal(const key: String): Single;
begin
 result := atof (vleGlobals.Values[key]);
end;

function TMainForm.GetIntGlobal(const key: String): Integer;
begin
 result := atoi (vleGlobals.Values[key]);
end;

function TMainForm.GetLayerProcessor: TLayerProcessor;
var
   i: Integer;
begin
 result := nil;
 Repeat
  for i := 0 to Length(lp_pool) - 1 do
   if not lp_pool[i].Busy then
     begin
      result := lp_pool[i];
      break;
     end;
  Sleep(50);
 Until (result <> nil);
end;

procedure TMainForm.WaitThreads(timeOut: DWORD);
var
   hList: TWOHandleArray;
       i: Integer;
begin
 //
 hList[0] := lproc.RequestEvent;
 for i := 1 to Length(lp_pool) do
   hList[i] := lp_pool[i - 1].RequestEvent;

 WaitForMultipleObjects( Length(lp_pool) + 1, @hList, True, timeOut);
end;

procedure TMainForm.ProducePhotonFile;
var
   lcnt: Integer;
    dir: array of TLayerHeader;
    ofs: Int64;
     nl: Integer;
     ms: TMemoryStream;

begin
 //.
 lcnt := Max(1, IntGlobals['Total layers']);
 SetLength (dir, lcnt);

 ms := TMemoryStream.Create;
 lproc.DeflateImage(ms);


 with phFile do
  begin
   pHeader.cnt_layers := lcnt;

   pHeader.layer_th := FloatGlobals['Layer thickness (mm)'];
   pHeader.exp_time := FloatGlobals['Normal exposure time (s)'];
   pHeader.exp_bottom := FloatGlobals['Bottom exposure time'];
   pHeader.cnt_bottom := IntGlobals['Bottom layers'];

   for nl := 0 to lcnt - 1 do
    begin
     dir[nl].height := pHeader.layer_th * nl;
     if nl >= pHeader.cnt_bottom then
        dir[nl].exp_time := pHeader.exp_time
     else
        dir[nl].exp_time := pHeader.exp_bottom;


    end;


   phFile.SetLayers (dir, False);
   phFile.RebuildMeta;

   for nl := 0 to lcnt - 1 do
    begin
     ofs := phFile.Position;
     dir[nl].offset := ofs;
     dir[nl].data_l := ms.Size;

     phFile.Write(ms.Memory^, ms.Size);
    end;

   phFile.SetLayers (dir, True); // rewrite with offsets

  end;

 ms.Free;
end;

procedure TMainForm.btnProcessLayersClick(Sender: TObject);
var
   lcnt: Integer;
   pcnt: Integer;
   lidx: Integer;
   llst: TObjectList;
   norm: Boolean;
   args: TStrMap;
   prcs: TLayerProcessor;
    dst: TPhotonFile;
    blk: DWORD;
    dir: array of TLayerHeader;
    raw: PByteArray2GB;
    prg: String;



     ls: TMemoryStream;
     nl: Integer;
     nc: Integer;
     pt: TProfileTimer;


begin
 if not lproc.Inflated then exit;


 prg := vleGlobals.Values['Interleave program'];

 for nl := 0 to Length(lp_pool) - 1 do
   with lp_pool[nl] do
    begin
     CoarseNB := IntGlobals['Coarse neighbors'];
     ScriptName := FindConfigFile (vleGlobals.Values['LUA Script']);
    end;
 WaitThreads(20000);

 pt := TProfileTimer.Create;
 dst := TPhotonFile.Create;

 dst.SetSize (phFile.Layers[0].offset); // all headers and preview expected before first layer data!

 dst.Position := 0;
 dst.Write(phFile.Memory^, dst.Size);   // copy meta-data and preview data
 dst.ParseBuffer;                       // extract original data, include preview images


 lcnt := phFile.LayersCount;

 ODS('[~T/~B].~C0E #DBG: processing start~C07');

 SetLength (dir, lcnt * Length(prg));       // pre-alloc oversized for safety

 btnProcessLayers.Enabled := False;

 pt.StartOne();

 llst := TObjectList.Create(TRUE);
 // stage 1: replicate and process layers
 with phFile.pHeader^ do
 for nl := 0 to lcnt - 1 do
  begin
   norm := (nl >= cnt_bottom); // not bottom layer
   nc := 0;
   if norm then
      nc := 1 + (nl - cnt_bottom) mod Length(prg);


   ls := TMemoryStream.Create;
   lidx := llst.Add(ls);

   // no action program
   if prg[nc] = '0' then
    begin
     phFile.StoreImageToStream (ls, nl); // odd layers typically save with no changes
     dir[lidx] := phFile.Layers[nl]^;      // reserve layer header, but not update now
    end
   else
    begin
     // REPLICATION WARNING: used same height for coarsed and original layer

     if cbxAddLayers.Checked and norm then
      begin
       phFile.StoreImageToStream (ls, nl);
       dir[lidx] := phFile.Layers[nl]^;  // reserve layer header, but not update now

       ls := TMemoryStream.Create;
       lidx := llst.Add(ls);
      end;

     // multithreaded processing: get free not-busy thread from pool for lease. It need time...
     prcs := GetLayerProcessor;
     prcs.AddRequest('set_file', phFile);                // source data for inflate
     prcs.AddRequest('set_new_header', @dir[lidx]);
     prcs.AddRequest('inflate_image', Ptr(nl));          // layer image unpack

     args := TStrMap.Create();
     args.Assign(vleGlobals.Strings);
     args.Values['program_code'] := prg[nc];

     prcs.AddRequest('ps_layer', args);
     prcs.AddRequest('deflate_image', ls);              // layer image pack to RLE stream
    end;


   if pt.Elapsed > 30 then
    begin
     pt.StartOne;
     pbStatus.Position := 100 * nl div lcnt;
     lbInfo.Caption := 'Processed layer  ' + IntToStr(nl);
     Application.ProcessMessages;
    end;

  end;

 SetLength (dir, llst.Count);// actualize layers amount
 // wait all request complete
 WaitThreads (25000);

 // stage 2: combine deflated data into new photon file
 dst.SetLayers(dir, False);   // update layers amount and cached content

 dst.pHeader.cnt_layers := llst.Count;
 dst.RebuildMeta;  // prepare all headers and store preview images

 for nl := 0 to llst.Count - 1 do
  begin
   ls := TMemoryStream (llst[nl]);

   blk := dst.Position;
   dir[nl].offset := blk;
   dir[nl].data_l := ls.Size;

   if dst.Size < blk then
      dst.SetSize (blk);
   dst.Write(ls.Memory^, ls.Size); // saving deflated layer into file
  end;


 wprintf('[~T/~B]. #DBG: processing complete, produced %d layers from %d, sizeof file %.3f MiB',
                [llst.Count, lcnt, dst.Size / MEBIBYTE]);

 btnProcessLayers.Enabled := True;

 dst.SetLayers(dir, True);               // update layers content inside file

{ raw := dst.LayerData[0];
 if not CompareMem (raw, phFile.LayerData[0], ls.Size) then
    wprintf('[~T].~C0C #WARN~C07: repack layer 0 produced different RLE data, bytes-dump: %x !', [raw[0]]); }


 // load updated data back
 phFile.LoadFromStream(dst);
 phFile.ParseBuffer;
 // lproc.InflateImage(phFile, 0);

 sbLayerSelect.Position := 0;
 sbLayerSelect.Min  := 0;
 sbLayerSelect.Max  := llst.Count - 1;

 // finalization
 llst.Free;
 dst.Free;
 SetLength (dir, 0);

 self.FormResize(self);
end;

procedure TMainForm.btnLoadImageClick(Sender: TObject);
const
   XRES = LCD_DEFAULT_W / 68.04 * 25.4;
   YRES = LCD_DEFAULT_H / 120.96 * 25.4;


var
   raw: array [0..LCD_DEFAULT_H - 1] of Pointer;
   bmp: TBitmap;
   imm: TBitmap;
   rot: Boolean;
    sl: PByteArray;
    sr: TRect;
    dr: TRect;
    cx: Single;
    cy: Single;
    dw: Integer;
    dh: Integer;
    rs: Single;
     x: Integer;
     y: Integer;
     s: String;
begin
 uiOpenDialog.Filter := 'Bitmap files|*.bmp';
 uiOpenDialog.FilterIndex := 1;
 if not uiOpenDialog.Execute then exit;

 // with layerOut.Picture do

 bmp := TBitmap.Create();
 bmp.LoadFromFile (uiOpenDialog.FileName);

 imm := TBitmap.Create();
 imm.PixelFormat := pf8bit;

 s := InputBox('Resolution', 'Image resolution in DPI', '600');
 rs := atof(s);
 if (rs <= 0) then rs := 96.0;

 cx := bmp.Width / rs * 25.4;
 cy := bmp.Height / rs * 25.4;

 lbInfo.Caption := Format('Image size: %.1f x %.1f mm. ', [cx, cy]);

 cx := XRES / rs;
 cy := YRES / rs;
 lbInfo.Caption := lbInfo.Caption + Format('Resize ratio X = %.3f, Y = %.3f', [cx, cy]);

 dw := Round (bmp.Width * cx);
 dh := Round (bmp.Height * cy);

 if (dw > LCD_DEFAULT_H) or (dh > LCD_DEFAULT_W) then
   begin
    wprintf('~C0C #WARN:~C07 target resolution to large: %d x %d, will be cropped!', [dw, dh]);
    dw := Math.Min(dw, LCD_DEFAULT_H);
    dh := Min(dh, LCD_DEFAULT_W);
   end;


 sr.SetLocation(0, 0);
 sr.Width := bmp.Width;
 sr.Height := bmp.Height;
 dr.SetLocation(0, 0);
 dr.Width := dw;
 dr.Height := dh;


 if (dw > dh) then
  begin // rotate need
   dr.SetLocation ( (LCD_DEFAULT_H - dw) div 2, (LCD_DEFAULT_W - dh) div 2 );
   imm.SetSize(LCD_DEFAULT_H, LCD_DEFAULT_W); // make wide intermediate bitmap
   imm.Canvas.CopyRect(dr, bmp.Canvas, sr);   // color conversion if need
   rot := True;
  end
 else
  begin
   dr.SetLocation ( (LCD_DEFAULT_W - dw) div 2, (LCD_DEFAULT_H - dh) div 2 );
   imm.SetSize (LCD_DEFAULT_W, LCD_DEFAULT_H); // make narrow intermediate bitmap
   imm.Canvas.CopyRect(dr, bmp.Canvas, sr);
   rot := False;
  end;

 // TODO: black-white coarse colors

 bmp.FreeImage;
 bmp.PixelFormat := pf8bit;
 bmp.SetSize (LCD_DEFAULT_W, LCD_DEFAULT_H);

 if rot then
  begin
   Assert (bmp.Width <= imm.Height);
   // simple rotate

   for y := 0 to imm.Height - 1 do
       raw[y] := imm.ScanLine[y];

   for y := 0 to bmp.Height - 1 do
    begin
     sl := bmp.ScanLine [y];
     for x := 0 to bmp.Width - 1 do
         sl[x] := PByteArray(raw[x])^[y];
    end;
  end
 else
  begin
   bmp.Assign(imm);
  end;

 // invert colors if need
 if cbxInverseImage.Checked then
   for y := 0 to bmp.Height - 1 do
    begin
     sl := bmp.ScanLine [y];
     for x := 0 to bmp.Width - 1 do
         sl [x] := 255 - sl [x];
    end;


 lproc.ImportRAW(bmp);
 SetDefValue('Total layers', 4);
 SetDefValue('Bottom layers', 1);
 SetDefValue('Bottom exposure time', 10);
 SetDefValue('Normal exposure time (s)', 3);

 FloatGlobals['Bed dimension X'] := phFile.pHeader.bed_sx;
 FloatGlobals['Bed dimension Y'] := phFile.pHeader.bed_sy;
 FloatGlobals['Bed dimension Z'] := phFile.pHeader.bed_sz;

 phFile.Cleanup;
 // creating previews
 imm.FreeImage;
 imm.PixelFormat := pf15bit;
 imm.SetSize(648, 425);
 imm.Canvas.Brush.color := clBlue;
 imm.Canvas.Brush.Style := bsSolid;
 imm.Canvas.FillRect(Rect(0, 0, imm.Width, imm.Height));


 sr.SetLocation (0, 0);
 sr.Width := bmp.Width;
 sr.Height := bmp.Height;
 // medium preview
 dr := ScaleFit(imm.Width, imm.Height, bmp.Width, bmp.Height);
 imm.Canvas.CopyRect(dr, bmp.Canvas, sr);
 phFile.DeflatePreview (imm, 0);

 // small preview
 imm.SetSize(198, 127);

 imm.Canvas.FillRect(Rect(0, 0, imm.Width, imm.Height));

 dr := ScaleFit(imm.Width, imm.Height, bmp.Width, bmp.Height);
 imm.Canvas.CopyRect(dr, bmp.Canvas, sr);
 phFile.DeflatePreview (imm, 1);

 imm.Free;
 bmp.Free;

 ProducePhotonFile;
 lproc.InflateImage(phFile, 0);
 sbLayerSelect.Max := phFile.LayersCount - 1;


 phFile.InflatePreview(preview0, 0);
 phFile.InflatePreview(preview1, 1);
 ShowPreview (0);
 btnSaveFile.Enabled := True;
end;

procedure TMainForm.btnOpenFileClick(Sender: TObject);
var
    fs: TFormatSettings;

begin
 fs := TFormatSettings.Create('en-US');
 uiOpenDialog.Filter := 'PHOTON files|*.photon';
 uiOpenDialog.FilterIndex := 1;

 if uiOpenDialog.Execute() and
      ( phFile.LoadParseFile(uiOpenDialog.FileName) > 0 ) then
  with phFile.pHeader^, vleGlobals do
   begin
    open_mode := True;
    vleGlobals.Strings.BeginUpdate;
    Values['Layer thickness (mm)']       := FormatFloat('0.##', layer_th, fs);
    Values['Normal exposure time (s)']   := FormatFloat('0.#', exp_time, fs);
    Values['Off time (s)']               := FormatFloat('0.#', off_time, fs);
    Values['Total layers']               := IntToStr (cnt_layers);
    Values['Bottom exposure time']       := FormatFloat('0.#', exp_bottom, fs);
    Values['Bottom layers']              := IntToStr (cnt_bottom);
    Values['Bed dimension X']            := FormatFloat('0.##', bed_sx, fs);
    Values['Bed dimension Y']            := FormatFloat('0.##', bed_sy, fs);
    Values['Bed dimension Z']            := FormatFloat('0.##', bed_sz, fs);
    Values['X Resolution']               := IntToStr (LCD_res_X);
    Values['Y Resolution']               := IntToStr (LCD_res_Y);
    vleGlobals.Strings.EndUpdate;

    sbLayerSelect.Position := 0;
    sbLayerSelect.Min  := 0;
    sbLayerSelect.Max  := cnt_layers - 1;


    phFile.InflatePreview(preview0, 0);
    ShowPreview (0);
    Application.ProcessMessages;

    phFile.InflatePreview(preview1, 1);
 //    lproc.InflateImage(phFile, 0);
    lproc.AddRequest('set_file', phFile);
    lproc.AddRequest('inflate_image', nil);

    if cnt_layers > 0 then
      begin
       btnSaveFile.Enabled := True;
       btnProcessLayers.Enabled := True;
      end;

    open_mode := False;
    // RedrawLayer
   end;

end;

procedure TMainForm.btnSaveFileClick(Sender: TObject);
begin
 if uiSaveDialog.Execute then
    phFile.SaveToFile(uiSaveDialog.FileName);
end;

procedure TMainForm.btnSelectScriptClick(Sender: TObject);
var
   i: Integer;
begin
 uiOpenDialog.Filter := 'Lua script|*.lua';
 if not uiOpenDialog.Execute then exit;
 vleGlobals.Values['LUA Script'] := uiOpenDialog.FileName;
 for i := 0 to Length(lp_pool) - 1 do
     lp_pool[i].ScriptName := uiOpenDialog.FileName
end;

procedure TMainForm.cbxShowPreview0Click(Sender: TObject);
begin
 if not cbxShowPreview0.Focused then exit;
 cbxShowPreview1.Checked := not cbxShowPreview0.Checked;
 ShowPreview (IfV(cbxShowPreview0.Checked, 0, 1));
end;

procedure TMainForm.cbxShowPreview1Click(Sender: TObject);
begin
 if not cbxShowPreview1.Focused then exit;
 cbxShowPreview0.Checked := not cbxShowPreview1.Checked;
 ShowPreview (IfV(cbxShowPreview0.Checked, 0, 1));
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
var
   i: Integer;

begin
 lproc.StopThread;
 for i  := 0 to Length(lp_pool) - 1 do
    lp_pool[i].StopThread();
 CanClose := TRUE;
end;

procedure TMainForm.FormCreate(Sender: TObject);
var
   i: Integer;
begin
 phFile := TPhotonFile.Create;
 lproc  := TLayerProcessor.Create (False, 'ps_layer_ui');
 lproc.WaitStart;

 SetLength (lp_pool, CPUCount);

 for i  := 0 to Length(lp_pool) - 1 do
  begin
   lp_pool[i] := TLayerProcessor.Create (False, 'ps_layer_' + IntToStr(i));
   lp_pool[i].WaitStart();
  end;


 preview0 := TBitmap.Create;
 preview1 := TBitmap.Create;
 layerOut.ControlStyle := layerOut.ControlStyle + [csOpaque];
 orig_proc := WindowProc;
 WindowProc := PatchWindowProc;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
var
   i: Integer;
begin
 lproc.WaitStop (1000);
 TerminateThread (lproc.Handle, 0);
 lproc.WaitStop (1000);

 for i  := 0 to Length(lp_pool) - 1 do
  begin
   lp_pool[i].WaitStop(1000);
   FreeAndNil (lp_pool[i]);
  end;


 FreeAndNil (phFile);
 FreeAndNil (lproc);
 FreeAndNil (preview0);
 FreeAndNil (preview1);
end;


procedure TMainForm.FormResize(Sender: TObject);
begin
 if cbxShowPreview0.Checked then
    ShowPreview(0)
 else
  if cbxShowPreview1.Checked then
    ShowPreview(1)
  else
    RedrawLayer;
end;

procedure TMainForm.RedrawLayer;
var
   vis_rect: TRect;
   bmp_rect: TRect;
      space: TRect;
      ratio: Single;
        bmp: TBitmap;
        plh: PLayerHeader;

begin
 lproc.WaitRequests();
 if not lproc.Inflated or lproc.Busy then exit;

 bmp := TBitmap.Create;
 with layerOut do
 try
   lproc.ExportRAW(bmp);
   space := TRect.Empty;

   space.Width  := layerOut.Width;
   space.Height := layerOut.Height;

   vis_rect := space; // default it

   Canvas.Pen.color := clRed;
   Canvas.Brush.Color := clYellow;
   Canvas.Brush.Style := bsSolid;
   Canvas.Rectangle(space);

   space.Height := space.Height - 30; // for text out

   vis_rect.SetLocation(1, 1);

   // this need for output correct
   Picture.Bitmap.SetSize(layerOut.Width, layerOut.Height);


   ratio := space.Width / space.Height; // nominal 0.5625

   if ratio >= LCD_DEFAULT_R then  // widht is over, correcting it
    begin
     vis_rect.Height := space.Height - 1;
     vis_rect.Width  := Trunc(vis_rect.Height * LCD_DEFAULT_R);
    end
   else
    begin
     vis_rect.Width  := space.Width - 1;
     vis_rect.Height := Trunc(vis_rect.Width / LCD_DEFAULT_R);
    end;


   bmp_rect := TRect.Empty;
   bmp_rect.Width  := LCD_DEFAULT_W;
   bmp_rect.Height := LCD_DEFAULT_H;
   Canvas.CopyRect (vis_rect, bmp.Canvas, bmp_rect);
   Repaint;
   Canvas.Pen.Color := clBlack;

   plh := phFile.Layers[sbLayerSelect.Position];
   if Assigned (plh) then
    begin
     Canvas.TextOut(10, space.Height + 2, 'Layer ' + IntToStr(sbLayerSelect.Position));
     Canvas.TextOut(10, space.Height + 15, Format('Exp_t: %.1f, Off_t: %.1f, Z: %.3f', [plh.exp_time, plh.off_time, plh.height]));
    end;


 finally
  FreeAndNil (bmp);
 end;
end;

procedure TMainForm.sbLayerSelectScroll(Sender: TObject; ScrollCode: TScrollCode; var ScrollPos: Integer);
begin
 cbxShowPreview0.Checked := False;
 cbxShowPreview1.Checked := False;
 lproc.InflateImage(phFile, sbLayerSelect.Position);
 RedrawLayer;
end;

procedure TMainForm.SetDefValue(const key: String; val: Integer);
begin
 open_mode := True;
 if vleGlobals.Values[key] = '0' then
    vleGlobals.Values[key] := IntToStr(val);
 open_mode := False;
end;

procedure TMainForm.SetFloatGlobal(const key: String; const Value: Single);
begin
 open_mode := True;
 vleGlobals.Values[key] := FormatFloat('0.0###', Value);
 open_mode := False;
end;

procedure TMainForm.ShowPreview(index: Integer);
var
   vis_rect: TRect;
   bmp_rect: TRect;
  bmp_ratio: Single;
      ratio: Single;

        bmp: TBitmap;

begin
 //
 bmp := preview0;
 if 1 = index then
    bmp := preview1;

 with layerOut do
  try
   // phFile.InflatePreview(bmp, index);
   vis_rect := TRect.Empty;
   vis_rect.Width  := layerOut.Width;
   vis_rect.Height := layerOut.Height;

   Canvas.Pen.color := clLime;
   Canvas.Brush.Color := clYellow;
   Canvas.Brush.Style := bsSolid;
   Canvas.Rectangle(vis_rect);
   vis_rect.SetLocation(1, 1);

   bmp_rect := TRect.Empty;
   bmp_rect.Width := bmp.Width;
   bmp_rect.Height := bmp.Height;

   Picture.Bitmap.SetSize(layerOut.Width, layerOut.Height);

   bmp_ratio := bmp.Width / bmp.Height;

   vis_rect.Height := vis_rect.Height - 2;
   vis_rect.Width  := vis_rect.Width - 2;


   ratio := vis_rect.Width / vis_rect.Height; // nominal 0.5625

   if ratio >= bmp_ratio then  // widht is over, correcting it
     vis_rect.Width  := Trunc(vis_rect.Height * bmp_ratio)
   else
     vis_rect.Height := Trunc(vis_rect.Width / bmp_ratio);

   Canvas.CopyRect (vis_rect, bmp.Canvas, bmp_rect);
   Repaint;

  except
   on E: Exception do
     OnExceptLog('ShowPreview', E, TRUE);

  end;

end;


procedure TMainForm.vleGlobalsStringsChange(Sender: TObject);
var
   dv: Integer;
   nl: Integer;

begin
 if Assigned(phFile.pHeader) and not open_mode then
 with phFile.pHeader^, vleGlobals do
  begin
   // overriding values
   // TODO: need height recalc for posibility change layer thinknes // layer_th := atof(Values['Layer thickness (mm)']);
   exp_time := atof(Values['Normal exposure time (s)']);
   off_time := atof(Values['Off time (s)']);
   exp_bottom := atof(Values['Bottom exposure time']);
   cnt_bottom := atoi(Values['Bottom layers']);
   dv := atoi(Values['Bottom exp. decrement']);

   for nl := 0 to cnt_bottom - 1 do
     begin
      phFile.Layers[nl].exp_time := exp_bottom - dv * nl;
      phFile.Layers[nl].off_time := off_time;
     end;

   for nl := cnt_bottom to cnt_layers - 1 do
     begin
      phFile.Layers[nl].exp_time := exp_time;
      phFile.Layers[nl].off_time := off_time;
     end;
   phFile.SyncLayers;
  end;
end;

procedure TMainForm.PatchWindowProc;
var
   rect: TRect;
begin
 //
 if Message.Msg = WM_ERASEBKGND then
  begin
   rect.SetLocation (layerOut.Left, layerOut.Top);
   rect.Width := layerOut.Width;
   rect.Height := layerOut.Height div 2;
   InvalidateRect(Handle, rect, False);
  end;

 orig_proc (Message);
 if Message.Msg = WM_ERASEBKGND then
    FormResize(nil);

end;

end.
