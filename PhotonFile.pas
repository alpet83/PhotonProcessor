unit PhotonFile;

interface
uses Windows, Classes, StrClasses, Graphics, SysUtils, System.IOUTils, Math, Misc, WThreads, LuaTypes, Lua5, LuaEngine, LuaImports;

const
   LCD_DEFAULT_W = 1440;
   LCD_DEFAULT_H = 2560;
   LCD_DEFAULT_R = LCD_DEFAULT_W / LCD_DEFAULT_H;

type
    TPhotonFile = class;

    TPhotonFileHeader = packed record
       tag: UInt32;
      nope: UInt32;
      // dimensions
      bed_sx: Single;  // SHORT SIDE 1440 = 68.04 mm
      bed_sy: Single;  // LONG  SIDE 2560 = 120.96 mm
      bed_sz: Single;  // Vertical SIDE = 150 mm
        padding0: array [0..2] of Int32;

        layer_th: Single; // default value
        exp_time: Single;
      exp_bottom: Single; // time for bottom layers
        off_time: Single;
      cnt_bottom: Int32; // count of bottom layers
       LCD_res_x: UInt32;
       LCD_res_y: UInt32;

    preview0_ofs: UInt32;
      layers_ofs: UInt32;  // list of layers records
      cnt_layers: Int32;   // count of layers
    preview1_ofs: UInt32;

       unknown_0: Int32;
     project_typ: Int32; // LightCuring/Projection type // (1=LCD_X_MIRROR, 0=CAST)
        padding1: array [0..5] of Int32;
    end;


    PPhotonFileHeader = ^TPhotonFileHeader;

    TPreviewHeader = packed record
       res_x: UInt32;
       res_y: UInt32;
      offset: UInt32;  // image data offset
      data_l: UInt32; // size of RAW data in bytes
     padding: array [0..3] of Int32;
    end;


    PPreviewHeader = ^TPreviewHeader;

    TLayerHeader = packed record
       height: Single;
     exp_time: Single;
     off_time: Single;
       offset: UInt32;
       data_l: UInt32;
     reserved: array [0..3] of Int32;
    end; // TLayerHeader

    PLayerHeader = ^TLayerHeader;

    TLayerLine = array [0..LCD_DEFAULT_W - 1] of Byte;
    TLayerRAW  = array [0..LCD_DEFAULT_H - 1] of TLayerLine;

    PLayerLine = ^TLayerLine;
    PLayerRAW  = ^TLayerRAW;


    // layer process thread can process queue of layer object
    TLayerProcessor = class (TWorkerThread)
    private
       FInflated: Boolean;
     FTempHeader: TLayerHeader;
      FNewHeader: PLayerHeader;
     FScriptName: String;


      procedure  SetScriptName(const Value: String);
      procedure  PushPhotonObject;
      procedure  PushLayerObject;
      function   GetLayerHeader: PLayerHeader;
      function   GetNewLayerHeader: PLayerHeader;
      procedure  SetNewLayerHeader(const Value: PLayerHeader);
    function GetRawData: PLayerRAW;
    protected

     coarse_nb: Integer;    // default value
       n_layer: Integer;
       ph_file: TPhotonFile;
      raw_data: TLayerRAW;
            le: TLuaEngine;

      procedure  ProcessInit; override;
      function   ProcessRequest (const rqs: String; rqobj: TObject): Integer; override;

    public

      property          CoarseNB: Integer      read coarse_nb write coarse_nb;
      property          Inflated: Boolean      read FInflated;
      property        ScriptName: String       read FScriptName write SetScriptName;
      property       LayerHeader: PLayerHeader read GetLayerHeader;
      property    NewLayerHeader: PLayerHeader read GetNewLayerHeader write SetNewLayerHeader;
      property           RawData: PLayerRAW    read GetRawData;

      { C & D }
      constructor Create (CreateSuspended: Boolean; const sName: String; bWindowed: Boolean = FALSE );

      { proc & func }
      procedure  CoarseStep (zone: TRect; nb_min: Integer = 7);            // image coarsening via details removal (edge light -> dark)
      function   InflateImage (pf: TPhotonFile; nLayer: Integer): Integer; // unpack RLE data to grayscale internal format
      function   DeflateImage (dst: TMemoryStream): Integer;               // pack grayscale image to RLE

      procedure  ExportRAW (dst: Graphics.TBitmap);
      function   ImportRAW (src: Graphics.TBitmap): Boolean;               // required 8-bit WB image!


    end; // TLayerProcess thread class


    TPhotonFile = class(TBytesStream)
    private
     function GetHeader: PPhotonFileHeader;
     function GetLayer(i: Integer): PLayerHeader;
     function GetLayersCount: Integer;
     function GetPreviewHeader(i: Integer): PPreviewHeader;
     function GetLayerData(i: Integer): PByteArray2GB;
    protected
     FPrevHeader: array [0..1] of TPreviewHeader;
       FPrevData: array [0..1] of Pointer;
         FLayers: array of TLayerHeader;

     procedure  LoadPreview(index: Integer);
     procedure  SavePreview(index: Integer);

    public

     property   pHeader: PPhotonFileHeader read GetHeader;

     property   LayerData[i: Integer]: PByteArray2GB read GetLayerData;
     property   Layers[i: Integer]: PLayerHeader read GetLayer;
     property   LayersCount: Integer read GetLayersCount;
     property   PreviewHeader[i: Integer]: PPreviewHeader read GetPreviewHeader;


     // C & D
     constructor Create;
     destructor  Destroy; override;

     // functions
     procedure  Cleanup;

     function   DeflatePreview (src: Graphics.TBitmap; index: Integer): Integer;
     function   InflatePreview (dst: Graphics.TBitmap; index: Integer): Integer;

     function   LoadParseFile(const sFileName: String): Integer;

     function   ParseBuffer: Integer;

     procedure  RebuildMeta;            // writes all headers and preview to begin of stream
     procedure  SetLayers(src: array of TLayerHeader; upd_direct: Boolean = False);
     procedure  SyncLayers;

     procedure  StoreImageToStream (ms: TMemoryStream; index: Integer);
    end;

const
   PREVIEW_HDR_SZ = SizeOf(TPreviewHeader);


procedure AlignStream4(ms: TCustomMemoryStream);

implementation
uses LuaTools;


const
  RLE_FLAG = $20;


procedure AlignStream4(ms: TCustomMemoryStream);
var
   pad: Int64;
begin
 pad := 0;
 if ms.Position and 3  > 0 then
    ms.Write(pad, 4 - (ms.Position and 3));

end;

{ TPhotonFile }

procedure TPhotonFile.Cleanup;
begin
 SetLength(FLayers, 0);
 FreeMem (FPrevData[0]);
 FreeMem (FPrevData[1]);

 FPrevData[0] := nil;
 FPrevData[1] := nil;
end;

constructor TPhotonFile.Create;
begin
 SetSize(SizeOf(TPhotonFileHeader));
 ZeroMemory(Memory, SizeOf(TPhotonFileHeader));

 with pHeader^ do
  begin
   tag := $12FD0019; // version 1.3.6 ?
   nope := 1;
   bed_sx := 68.04;
   bed_sy := 120.96;
   bed_sz := 150;
   layer_th := 0.05;
   LCD_res_x := 1440;
   LCD_res_y := 2560;
   exp_time := 10;
   off_time := 1;
   cnt_bottom := 8;
   exp_bottom := 35;
   project_typ := 1;
  end;
end;

destructor TPhotonFile.Destroy;
begin
 Cleanup;
 inherited;
end;

function TPhotonFile.GetHeader: PPhotonFileHeader;
begin
 result := Memory;
end;

function TPhotonFile.GetLayer(i: Integer): PLayerHeader;
begin
 result := nil;
 if Assigned(pHeader) and (i >= 0) and (i < Length(FLayers)) then
     result := @FLayers[i];
end;

function TPhotonFile.GetLayerData(i: Integer): PByteArray2GB;
begin
 result := Memory;
 result := @result[FLayers[i].offset];
end;

function TPhotonFile.GetLayersCount: Integer;
begin
 result := 0;
 if Assigned(pHeader) then
    result := pHeader.cnt_layers;
end;

function TPhotonFile.GetPreviewHeader(i: Integer): PPreviewHeader;
begin
 result := @FPrevHeader [i and 1];
end;


function TPhotonFile.DeflatePreview(src: Graphics.TBitmap; index: Integer): Integer;
var
   dst: PWordArray;
   pxl: PWordArray;
   ofs: Integer;
   prv: WORD;
    cl: WORD;
    cc: WORD;
     x: Integer;
     y: Integer;

begin
 result := 0;
 if (src.PixelFormat <> pf15bit) and (src.PixelFormat <> pfCustom) then
  begin
   PrintError('DeflatePreview: Source image must be 15 bit pixel format');
   exit;
  end;


 GetMem (dst, src.Width * src.Height * 2); // oversize

 prv := PWord(src.ScanLine[0])^; // first pixel init

 ofs := 0;
 cc := 0;
 // std matrix scan loop

 for y := 0 to src.Height - 1 do
  begin
   pxl := src.ScanLine [y];
   for x := 0 to src.Width - 1 do
    begin
     cl := pxl [x] and $7FFF;
     if (prv = cl) and (cc < $FFF) then
       Inc (cc)
     else
      begin
       Inc (ofs, 1 + Integer(cc >= 1));
       cc := 0;
       prv := cl;
      end;


     cl := (cl and $1F) or ( (cl and $FFE0) shl 1 ); // reserve one bit for RLE-flag
     if cc > 1 then
        cl := cl or RLE_FLAG;

     dst[ofs] := cl;
     dst[ofs + 1] := cc;
    end;
  end;

 if cc > 1 then Inc (ofs); // finalization

 result := ofs * 2;
 ReallocMem(dst, result);
 FPrevData[index] := dst;
 with FPrevHeader[index] do
  begin
   res_x := src.Width;
   res_y := src.Height;
   data_l := result;
  end;
end;

function TPhotonFile.InflatePreview(dst: Graphics.TBitmap; index: Integer): Integer;
var
   pph: PPreviewHeader;
   src: PWordArray;
   rle: WORD;
    cl: WORD;
    cc: WORD;
    np: WORD;
    di: Integer;
    py: Integer;
    sl: PWordArray;
     i: Integer;

 procedure PutPixel;
 var

    cy: Integer;
 begin
  cy := di div pph.res_x;
  // Assert (cy < pph.res_y, 'Abnormal dest coordinate!');
  if (cy < dst.Height) then
   begin
    if py <> cy then
       sl := dst.ScanLine[cy]; // this operation eats time

    sl[di mod dst.Width] := cl;
    py := cy;
   end;
  Inc (di);
 end;

begin
 result := 0;
 if pHeader = nil then exit;


 pph := @FPrevHeader [index];
 di := 0;
 wprintf('[~T/~B]. #PERF: Starting unpacking preview image %d ', [index]);


 with pph^ do
  begin

   dst.PixelFormat := pf15bit;
   dst.SetSize(res_x, res_y);
   py  := 0;
   sl := dst.ScanLine[py];

   src := FPrevData[index];
   i := 0;
   while i < (data_l div 2) do
    begin
     cl := src[i];
     rle := cl and RLE_FLAG;
     cl := cl and (not RLE_FLAG);
     cl := (cl and $1f) or ( (cl and $FF40) shr 1); // repack RRRRR GGGGG X BBBBB to 0 RRRRR GGGGG BBBB
     Inc (i);
     cc := 1;

     if rle > 0 then // more than one pixel
        begin
         Inc (cc, src[i] and $FFF);
         Inc(i);
        end;
     for np := 1 to cc do
        PutPixel;
    end; // while
   wprintf('[~T/~B]. #PERF: unpacked %d pixels, for picture %d x %d ', [di, res_x, res_y]);
  end;

end;

function TPhotonFile.LoadParseFile(const sFileName: String): Integer;
begin
 result := Windows.ERROR_FILE_NOT_FOUND;
 if not FileExists (sFileName) then exit;
 LoadFromFile(sFileName);
 wprintf('[~T/~B]. #DBG: Parsing file %s...', [sFileName]);
 result := ParseBuffer;
end; // LoadFile

procedure TPhotonFile.LoadPreview(index: Integer);
var
   src: PByteArray2GB;
   ofs: DWORD;
   pph: PPreviewHeader;
    cb: DWORD;

begin
 index := index and 1;
 src := Memory;
 if 0 = index then
    pph := @src[pHeader.preview0_ofs]
 else
    pph := @src[pHeader.preview1_ofs];

 FPrevHeader[index] := pph^;

 if FPrevData [index] <> nil then
    FreeMem (FPrevData [index]);

 FPrevData [index] := nil;

 cb := FPrevHeader[index].data_l;
 ofs := FPrevHeader[index].offset;

 if (cb = 0) or (ofs = 0) then exit;

 src := @src[ofs];

 GetMem(FPrevData[index], cb);
 CopyMemory(FPrevData[index], src, cb);
end;



function TPhotonFile.ParseBuffer: Integer;
var
   raw: PByteArray2GB;
   plh: PLayerHeader;
     i: Integer;
begin
 result := -1;
 if 0 = Size then exit; // no content
 result := -2;
 with pHeader^ do
  try
   // checking dimensions
   if IsNan(bed_sx) or IsNan (bed_sy) or IsNan (bed_sz) then exit;

   raw := Memory; // @Bytes;

   //wprintf('~C0E Printing zone dimensions XYZ:~C07 %.3f x %.3f x %.3f ', [bed_sx, bed_sy, bed_sz]);
   //wprintf('~C0E layers count %d, exposure time %.1f s ', [cnt_layers, exp_time]);
   //wprintf('~C0E bottom count %d, exposure time %.1f s ', [cnt_bottom, exp_bottom]);

   SetLength(FLayers, cnt_layers);

   // parsing previews
   LoadPreview(0);
   LoadPreview(1);


   // parsing layers
   for i := 0 to cnt_layers - 1 do
     begin
       plh := @raw [ UInt32(i * sizeof (TLayerHeader)) + layers_ofs];
       FLayers[i] := plh^;
     end;

   result := cnt_layers;
  except
   on E: Exception do
     OnExceptLog('TPhotonFile.ParseBuffer', E, TRUE);
  end;
end;

procedure TPhotonFile.RebuildMeta;
// must be filled headers, before call this proc!
begin
 SetSize (MEBIBYTE); // prevent realloc
 Seek (SizeOf(TPhotonFileHeader), soFromBeginning); // skip main header

 with pHeader^ do
  begin
   cnt_layers := Length(FLayers);
   SavePreview(0);
   SavePreview(1);

   layers_ofs := Position;
   Write (FLayers[0], SizeOf(TLayerHeader) * cnt_layers);
   AlignStream4 (self);
   SetSize(Position); // meta-data write complete!
  end;

end;

procedure TPhotonFile.SavePreview(index: Integer);
begin
 if 0 = index then
    pHeader.preview0_ofs := Position
 else
    pHeader.preview1_ofs := Position;

 FPrevHeader[index].offset := Position + PREVIEW_HDR_SZ;
 Write (FPrevHeader[index], PREVIEW_HDR_SZ);
 if Assigned(FPrevData[index]) and (FPrevHeader[index].data_l > 0) then
    Write (FPrevData[index]^,  FPrevHeader[index].data_l);

 AlignStream4 (self);
end;

procedure TPhotonFile.SetLayers(src: array of TLayerHeader; upd_direct: Boolean);
var
    i: Integer;
begin
 SetLength (FLayers, Length(src));
 for i := 0 to Length(src) - 1 do
   FLayers[i] := src[i];

 if not upd_direct then exit;
 SyncLayers;

end;

procedure TPhotonFile.StoreImageToStream(ms: TMemoryStream; index: Integer);
var
   data: PByteArray2GB;

begin
 data := Memory;
 if Assigned(data) then
 with pHeader^, FLayers[index] do
 if index < cnt_layers then
  begin
   data := @data[offset];
   ms.Position := 0;
   ms.SetSize(data_l);
   ms.Write(data^, data_l);
  end;
end;

procedure TPhotonFile.SyncLayers;
var
  plh: PLayerHeader;
  raw: PByteArray2GB;
    i: Integer;

begin
 raw := Memory;
 raw := @raw[pHeader.layers_ofs];

 for i := 0 to Length(FLayers) - 1 do
  begin
   plh := @raw[i * SizeOf(TLayerHeader)];
   plh^ := FLayers[i];
  end;

end;

{ TLayerProcessor }

procedure TLayerProcessor.CoarseStep;

var
   tmp: PLayerRAW;
   sum: Integer;
   tgt: Integer;
    cc: array [0..8] of BYTE;
     i: Integer;
     x: Integer;
     y: Integer;
begin

 New (tmp);
 tgt := 255 * nb_min;

 if zone.IsEmpty then
  begin
   zone.SetLocation(2, 2);
   zone.Right  := LCD_DEFAULT_W - 2;
   zone.Bottom := LCD_DEFAULT_H - 2;
  end;

 zone.Left   := Max (zone.Left, 1);
 zone.Top    := Max (zone.Top,  1);

 zone.Right  := Min (zone.Right,  LCD_DEFAULT_W - 2);
 zone.Bottom := Min (zone.Bottom, LCD_DEFAULT_H - 2);


 try
   Move(raw_data, tmp^, SizeOf (raw_data)); // fast copy
   FillChar(cc, SizeOf(cc), 0);

   for y := zone.Top to zone.Bottom do
    for x := zone.Left to zone.Right do
    if raw_data[y][x] > 0 then  // found lighted pixel, try to extinguish
     begin
      // if pixel on edge, not all neighbor pixel are 255, summ must be < 255 * 9
      Move (raw_data[y - 1][x - 1], cc[0], 3);
      Move (raw_data[y + 0][x - 1], cc[3], 3);
      Move (raw_data[y + 1][x - 1], cc[6], 3);
      sum := 0;
      for i := 0 to High(cc) do
          Inc(sum, cc[i]);

      if (sum <= tgt) then // need 'nb_min' neigbors, for prevent pixel off
          tmp^[y][x] := 0;

     end;

  Move(tmp^, raw_data, SizeOf (raw_data)); // fast save
 finally
  Dispose(tmp);
 end;
end;



constructor TLayerProcessor.Create;
begin
 inherited Create(CreateSuspended, sName, bWindowed);
 FScriptName := '';
 FInflated   := False;
end;

function TLayerProcessor.DeflateImage(dst: TMemoryStream): Integer;
var
   di: Integer;
    x: Integer;
    y: Integer;
   cl: Byte;
   cc: Byte;
   bb: PByteArray2GB;
begin
 result := 0;
 if not Inflated then exit;
 dst.SetSize (SizeOf (raw_data)); // impossible, but safe
 ZeroMemory (dst.Memory, dst.Size);

 di := 0;

 cl := raw_data[0][0];
 cc := 0;
 bb := dst.Memory;
 // WARN: in this scheme RLE lines not breaked, then Y increments
 for y := 0 to LCD_DEFAULT_H - 1 do
  for x := 0 to LCD_DEFAULT_W - 1 do
   begin
    if ( cl = raw_data[y][x] ) and (cc < 125) then
       Inc(cc)
    else
      begin
       bb[di] := cc or (cl and 128);
       Inc (di);
       cc := 1;
       cl := raw_data[y][x];
      end;

   end; // for matrix

 if cc > 0 then // last record
  begin
   bb[di] := cc or (cl and 128);
   Inc (di);
  end;



 dst.SetSize(di);
 result := di;
end;

procedure TLayerProcessor.ExportRAW(dst: Graphics.TBitmap);
var
   y: Integer;
begin
 dst.PixelFormat := pf8bit;
 dst.SetSize (LCD_DEFAULT_W, LCD_DEFAULT_H);

 try
  for y := 0 to LCD_DEFAULT_H - 1 do
      Move (raw_data[y], dst.ScanLine[y]^, SizeOf(TLayerLine));

 except
  on E: Exception do
    OnExceptLog('TLayerProcessor.ExportRAW', E);

 end;
end;

function  TLayerProcessor.ImportRAW;
var
   y: Integer;
begin
 result := False;

 if (src.Width <> LCD_DEFAULT_W) or (src.Height <> LCD_DEFAULT_H) then
  begin
   PrintError('ImportRAW image size invalid: ' + Format('%d x %d', [src.Width, src.Height]));
   exit;
  end;

 if src.PixelFormat <> pf8bit then
  begin
   PrintError('ImportRAW image pixel format invalid!');
   exit;
  end;

 try
  for y := 0 to LCD_DEFAULT_H - 1 do
      Move (src.ScanLine[y]^, raw_data[y], SizeOf(TLayerLine));

  FInflated := True;
  result := True;
 except
  on E: Exception do
    OnExceptLog('TLayerProcessor.ImportRAW', E);

 end;


end;



function TLayerProcessor.GetLayerHeader: PLayerHeader;
begin
 result := nil;
 if Assigned(ph_file) then
    result := ph_file.Layers[n_layer];
end;

function TLayerProcessor.GetNewLayerHeader: PLayerHeader;
begin
 result := FNewHeader;
 if result = nil then
    result := @FTempHeader;
end;

function TLayerProcessor.GetRawData: PLayerRAW;
begin
 result := @raw_data;
end;

function TLayerProcessor.InflateImage (pf: TPhotonFile; nLayer: Integer): Integer;
var
   psrc: PByteArray2GB;
   pdst: PByteArray2GB;
    plh: PLayerHeader;
     di: Integer;
     si: Integer;
     cl: Byte;
     cp: Byte;

begin
 //
 result := 0;
 psrc := pf.Memory;
 if nil = psrc then exit;
 self.n_layer := nLayer;
 Assert (Assigned(pf.Layers [nLayer]), 'Unassigned layer header ' + IntToStr(nLayer));

 plh := pf.Layers [nLayer];
 NewLayerHeader^ := plh^;

 pdst := @raw_data;
 di   := 0;

 Assert (Assigned(plh), Format('Invalid layer pointer for index %d', [nLayer]));

 with plh^ do
  try
   psrc := @psrc[offset];
   for si := 0 to data_l - 1 do
     begin
      if di >= SizeOf(raw_data) then
        begin
         wprintf('#WARN: inflate image size = %d, maximum = %d, breaking loops', [di, SizeOf(raw_data)]);
         break;
        end;

      cp := psrc[si] and 127;  // amount
      cl := psrc[si] shr 7;    // color
      // easy and SLOW unpack RLE
      while cp > 0 do
       begin
        pdst[di] := cl * 255;
        Dec(cp);
        Inc (di);
       end; // while
      // Inc(psrc);
     end; // for
   FInflated := (di > 0);
  except
   on E: Exception do
     OnExceptLog('TLayerProcessor.InflateImage', E, TRUE);

  end; //
  result := di;

end; // InflateImage

procedure TLayerProcessor.ProcessInit;
begin
  inherited;
 le := TLuaEngine.Create;
end;

function TLayerProcessor.ProcessRequest(const rqs: String; rqobj: TObject): Integer;
var
    sm: TStrMap;
    sp: TStringParam;
begin
 result := inherited ProcessRequest(rqs, rqobj);
 if rqs = 'set_new_header' then
   FNewHeader := Pointer(rqobj);

 if rqs = 'load_script' then
   begin
    sp := TStringParam (rqobj);
    FScriptName := sp.Value;
    FreeAndNil(sp);

    le.LoadScript(ScriptName);
    le.PushVal(ThreadName);
    le.SetGlobal('thread_name');
    if le.ScriptUpdated then
       le.Execute
    else
       PrintError('Script [' + ScriptName + '] load failed for ' + ThreadName);
   end;

 if (rqs = 'ps_layer') and Assigned(ph_file) then
 with ph_file.pHeader^ do
  try
   sm := TStrMap(rqobj);

   if ScriptName = '' then
     begin
      PrintError('ScriptName not specified for ' + ThreadName);
      exit;
     end;

   if not le.ScriptLoaded then
     begin
      le.LoadScript (ScriptName);
      le.Execute;
     end;


   // processing via script prepared RAW data //
   // TODO: prepare all params
   le.SetGlobal('def_layer_thickness', layer_th);
   le.SetGlobal('def_exposure_time', exp_time);
   le.SetGlobal('def_off_time', off_time);
   le.SetGlobal('def_bottom_time', exp_bottom);
   le.SetGlobal('bottom_layers', cnt_bottom);
   le.SetGlobal('def_coarse_neighbors', coarse_nb);

   le.SetGlobal('program_code', sm.Values['program_code']);

   PushPhotonObject;
   le.SetGlobal('photon_file');

   PushLayerObject;
   le.SetGlobal('layer');

   FreeAndNil (sm);
   le.CallFunc('process_layer');
  except
   on E: Exception do
      OnExceptLog('ProcessRequest("ps_layer")', E, True);
  end;


 if rqs = 'set_file' then
    ph_file := TPhotonFile(rqobj);

 if rqs = 'deflate_image' then
    DeflateImage (TMemoryStream(rqobj));

 if rqs = 'inflate_image' then
    InflateImage (ph_file, Integer(rqobj));

 if rqs = 'export_raw' then
    ExportRAW (TBitmap(rqobj));

end;


function __layer_coarse(L: lua_State): Integer; cdecl;
var

   rect: TRect;
     lp: TLayerProcessor;
     nb: Integer;
begin
 result := 1;
 lp := lua_objptr (L, 1);
 Assert ( Assigned(lp), 'WTF?' );
 nb := lp.coarse_nb;

 if lua_gettop(L) > 1 then
    nb := lua_tointeger(L, 2);

 rect.SetLocation(0, 0);
 rect.Width := LCD_DEFAULT_W;
 rect.Height := LCD_DEFAULT_H;

 if lua_gettop(L) > 5 then
  begin
   rect.Left := lua_tointeger(L, 3);
   rect.Top  := lua_tointeger(L, 4);
   rect.Right :=  lua_tointeger(L, 5);
   rect.Bottom := lua_tointeger(L, 6);
  end;

 lp.CoarseStep(rect, nb);
 lua_pushboolean(L, 1);
end;



function __layer_index(L: lua_State): Integer; cdecl; // read values
var
   key: String;
   plh: PLayerHeader;
    lp: TLayerProcessor;
begin
 result := 1;
 lp := lua_objptr (L, 1);
 key := LuaStrArg (L, 2);
 Assert ( Assigned(lp), 'WTF?' );
 plh := lp.NewLayerHeader;

 if key = 'exp_time' then
   lua_pushnumber(L, plh.exp_time)
 else
 if key = 'off_time' then
   lua_pushnumber(L, plh.off_time)
 else
 if key = 'height' then
    lua_pushnumber(L, plh.height)
 else
 if key = 'index' then
    lua_pushinteger(L, lp.n_layer)
 else
 if key = 'coarse' then
    lua_pushcfunction(L, __layer_coarse);
end;


function __layer_new_index(L: lua_State): Integer; cdecl;
var
   key: String;
   plh: PLayerHeader;
    lp: TLayerProcessor;
begin
 result := 0;
 lp := lua_objptr (L, 1);
 key := LuaStrArg (L, 2);
 if lua_gettop(L) < 3 then exit;

 plh := lp.NewLayerHeader;

 if key = 'height' then
    plh.height := lua_tonumber(L, 3)
 else
 if key = 'exp_time' then
    plh.exp_time := lua_tonumber(L, 3)
 else
 if key = 'off_time' then
    plh.off_time := lua_tonumber(L, 3);

end;

procedure TLayerProcessor.PushLayerObject;
begin
 // lua_pushptr (le.State, @raw_data);
 AssignMetaIndex (le.State, self, __layer_index, __layer_new_index, '__MT_LAYER');
end;

procedure TLayerProcessor.PushPhotonObject;
begin
 lua_pushptr(le.State, ph_file);
end;

procedure TLayerProcessor.SetNewLayerHeader(const Value: PLayerHeader);
begin
 AddRequest('set_new_header', TObject(Value));
end;

procedure TLayerProcessor.SetScriptName(const Value: String);
begin
 if FScriptName <> Value then
    AddRequest('load_script', TStringParam.Create(Value));
end;

end.
