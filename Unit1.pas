unit Unit1;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,QString,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,Winapi.ShellAPI,QJson,Vcl.Imaging.pngimage,System.Generics.Collections,System.Types,System.IOUtils;

type

  TXY = record
    X: Integer;
    Y: Integer;
  end;

  TForm1 = class(TForm)
    mmo_log: TMemo;
    lbl1: TLabel;
    procedure FormCreate(Sender: TObject);
  private
    { Private declarations }
  public
    { Public declarations }
    procedure WmDropFiles(var Msg: TMessage); message WM_DROPFILES;
    procedure DoUnPack(FileName:String);
    procedure PackPngAsEgretMoiveClip(const BasePath: String;const sheetName: string; TargetModelDir: String);
    function RunWait(FileName: string; WorkDir: String;Visibility: Integer): THandle;
    procedure ConvertToEgretMoiceClip(const JsonFile: String; FPS: Single;FrameCount: Integer; Offset: TList<TXY>);
    procedure DoRepack(FileName:String);
  end;


  TChunkIHDRHelper = class helper for TChunkIHDR
  public
    function GetPerPixelByteSize():Integer;

  end;


var
  Form1: TForm1;

implementation

{$R *.dfm}

{ TForm1 }

procedure TForm1.DoRepack(FileName: String);
var
  SourceDir , SheetName,TargetDir :String;
  json : TQJson;
begin

  json := TQJson.Create;
  json.LoadFromFile(ChangeFileExt(FileName,'.json'));
  if  Json.ValueByName('repacked','') = 'true' then
  begin
    Json.Free;
    mmo_log.Lines.Add('文件已经被重新打包,跳过:' + FileName);
    Exit;
  end;

  if DirectoryExists('.\worktemp') then
  begin
    TDirectory.Delete('.\worktemp',true);
  end;

  DoUnPack(FileName);
  SourceDir := '.\worktemp\';
  SheetName := ChangeFileExt(ExtractFileName(FileName),'.json');
  TargetDir := ExtractFileDir(FileName) + '\';
  PackPngAsEgretMoiveClip(SourceDir,SheetName,TargetDir);
end;

procedure TForm1.DoUnPack(FileName: String);
var
  jsonFileName:String;
  Json,frames,node : TQJson;
  i:Integer;
  Png : TPngImage;
  tempPng : TPngImage;
  W,H,X,Y:Integer;
  targetPath : String;
  AX,AY:Integer;
  pPngAlphaLine:PByte;
  pTempPngAlphaLine:PByte;
  PerPixelSize : Integer;
  ALineLen : Integer;
  XList : TStringList;
  PointJson:TQJson;
begin
  mmo_log.Lines.Add('开始处理:' + FileName);
  FileName := ChangeFileExt(FileName,'.png');
  if not FileExists(FileName) then
  begin
    mmo_log.Lines.Add('图集文件不存在:' + FileName);
    Exit;
  end;

  jsonFileName := ChangeFileExt(FileName,'.json');
  if not FileExists(jsonFileName) then
  begin
    mmo_log.Lines.Add('json描述文件不存在:' + jsonFileName);
    Exit;
  end;

  Json := TQJson.Create;
  json.LoadFromFile(jsonFileName);
  frames := Json.ItemByPath('.res');
  if  Json.ValueByName('repacked','') = 'true' then
  begin
    Json.Free;
    mmo_log.Lines.Add('文件已经被重新打包');
    Exit;
  end;

  if frames = nil then
  begin
    mmo_log.Lines.Add('无法找到 frames 子节点');
    Exit;
  end;

  targetPath := '.\worktemp';
  //targetPath := ChangeFileExt(FileName,'') + '_unpacked';

  if not DirectoryExists(targetPath) then
  begin
    if not ForceDirectories(targetPath) then
    begin
      raise Exception.Create('无法创建目录:' + targetPath );
    end;
  end;

  Png := TPngImage.Create;
  Png.LoadFromFile(FileName);
  XList := TStringList.Create;
  XList.Add((json.ItemByPath('mc.main.frameRate').AsFloat).ToString());

  PointJson := Json.ItemByPath('mc.main.frames');
  XList.Add(PointJson.Count.ToString());
  for I := 0 to PointJson.Count - 1 do
  begin
    XList.Add(PointJson.Items[i].ValueByName('x','0') + ' ' + PointJson.Items[i].ValueByName('y','0'));
  end;
  XList.SaveToFile(targetPath + '\x.txt');
  XList.Free;

//  for i := 0 to Png.Chunks.Count - 1 do
//  begin
//    mmo_log.Lines.Add('Chk: Png - ' + I .ToString + ':' + Png.Chunks.Item[i].Name);
//  end;

  PerPixelSize := Png.Header.GetPerPixelByteSize();

  for i := 0 to frames.Count - 1 do
  begin
    node :=  frames.Items[i];

    W := Node.IntByName('w',0);
    h := Node.IntByName('h',0);
    x := Node.IntByName('x',0);
    y := Node.IntByName('y',0);

    if (W <=0) or (H <=0) then
    begin
      mmo_log.Lines.Add('跳过 宽度高度 为0的图片:' + Node.Name);
      Continue;
    end;

    tempPng := TPngImage.Create;
    tempPng.CreateBlank(Png.Header.ColorType,png.header.BitDepth,w,h);

    ALineLen := TempPng.Width * PerPixelSize;

    //先直接拷贝像素数据
    for AY := 0 to tempPng.Height - 1 do
    begin
      pPngAlphaLine := PByte(Png.Scanline[AY + Y]);
      pTempPngAlphaLine := PByte(tempPng.Scanline[AY]);
      Inc(pPngAlphaLine,X * PerPixelSize);
      Move(pPngAlphaLine^,pTempPngAlphaLine^,ALineLen);
    end;


    //然后处理透明通道的数据
    if Png.Header.ColorType = COLOR_PALETTE  then
    begin
      tempPng.Palette := Png.Palette;

      //如果是调色板模式那么直接拷贝透明通道数据
      if Png.TransparencyMode <> ptmNone then
      begin
        tempPng.CreateAlpha();
        tempPng.Chunks.ItemFromClass(TChunktRNS).Assign(Png.Chunks.ItemFromClass(TChunktRNS));
      end;
    end else
    begin
      if Png.TransparencyMode <> ptmNone then
      begin
        tempPng.CreateAlpha();
        for AY := 0 to tempPng.Height - 1 do
        begin
          pPngAlphaLine := PByte(Png.AlphaScanline[AY + Y]);
          pTempPngAlphaLine := PByte(tempPng.AlphaScanline[AY]);
          Inc(pPngAlphaLine,X);
          Move(pPngAlphaLine^,pTempPngAlphaLine^,tempPng.Width);
        end;
      end;
    end;

//    for AX := 0 to tempPng.Chunks.Count - 1 do
//    begin
//      mmo_log.Lines.Add('Chk: TempPng - ' + AX .ToString + ':' + tempPng.Chunks.Item[AX].Name);
//    end;

    tempPng.SaveToFile(targetPath + '\' + node.Name + '.png');
    tempPng.Free;
  end;

  png.Free;
  Json.Free;

end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  ChangeWindowMessageFilter(WM_DROPFILES, MSGFLT_ADD);

  ChangeWindowMessageFilter(WM_COPYDATA, MSGFLT_ADD);

  ChangeWindowMessageFilter(WM_COPYGLOBALDATA , MSGFLT_ADD);

   DragAcceptFiles(Form1.Handle, True);
end;

procedure TForm1.WmDropFiles(var Msg: TMessage);
var
   P:array[0..511] of Char;
   i:Word;
begin
   Inherited;
   {$IFDEF WIN32}
      i:=DragQueryFile(Msg.wParam,$FFFFFFFF,nil,0);
   {$ELSE}
      i:=DragQueryFile(Msg.wParam,$FFFF,nil,0);
   {$ENDIF}
   for i:=0 to i-1 do
   begin
     DragQueryFile(Msg.wParam,i,P,512);
     DoRepack(StrPas(P));
   end;

   mmo_log.Lines.Add('所有文件处理完成');
end;

function TForm1.RunWait(FileName: string; WorkDir: String;
Visibility: Integer): THandle;
var
  zAppName: array [0 .. 102400] of Char;
  zCurDir: array [0 .. 255] of Char;
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
  ExitCode: Cardinal;
begin
  StrPCopy(zAppName, FileName);
  StrPCopy(zCurDir, WorkDir);
  FillChar(StartupInfo, SizeOf(StartupInfo), #0);
  StartupInfo.cb := SizeOf(StartupInfo);
  StartupInfo.dwFlags := STARTF_USESHOWWINDOW;
  StartupInfo.wShowWindow := Visibility;
  if not CreateProcess(nil, zAppName, nil, nil, False, Create_NEW_CONSOLE or
    NORMAL_PRIORITY_CLASS, nil, @zCurDir[0], StartupInfo, ProcessInfo) then
  begin
    Result := 0;
    Exit;
  end
  else
  begin
    WaitForSingleObject(ProcessInfo.hProcess, INFINITE);
    GetExitCodeProcess(ProcessInfo.hProcess, ExitCode);
  end;
end;

procedure TForm1.PackPngAsEgretMoiveClip(const BasePath: String;
const sheetName: string; TargetModelDir: String);
var
  DirName: String;
  cmdLine, PngFileName: String;
  Files: TStringDynArray;
  FilesStr, pngFile, temp, JsonFile: String;
  Offset: TList<TXY>;
  XY: TXY;
  FrameRate: Single;
  FrameCount: Integer;
  OffsetFile: TStringList;
  I: Integer;
  nPos: Integer;
  targetPng: String;
begin
  DirName := BasePath;

  if DirectoryExists(DirName) then
  begin
    Files := System.IOUtils.TDirectory.GetFiles(DirName, '*.png');

    targetPng := ChangeFileExt(sheetName, '.png');
    if Length(Files) > 0 then
    begin
      for pngFile in Files do
      begin
        temp := ExtractFileName(pngFile);
        if (temp <> 'stand.png') and (temp <> 'run.png') and (temp <> targetPng)
        then
          FilesStr := FilesStr + ' "' + temp + '"';
      end;

      cmdLine :=
        '.\texturepacker\bin\texturepacker --disable-rotation --trim-mode None --texture-format png8 --format pixijs --data '
        + sheetName + ' ' + FilesStr;
      RunWait(cmdLine, DirName, SW_HIDE);

      OffsetFile := TStringList.Create;
      OffsetFile.LoadFromFile(DirName + '\x.txt');
      FrameRate := OffsetFile[0].ToSingle();
      FrameCount := OffsetFile[1].ToInteger();
      OffsetFile.Delete(0);
      OffsetFile.Delete(0);

      Offset := TList<TXY>.Create();

      for I := 0 to OffsetFile.Count - 1 do
      begin
        nPos := OffsetFile[I].IndexOf(' ');
        XY.X := StrToInt(Copy(OffsetFile[I], 1, nPos));
        XY.Y := StrToInt(Copy(OffsetFile[I], nPos + 2, Length(OffsetFile[I])));
        Offset.Add(XY);
      end;

      JsonFile := DirName + '\' + sheetName;
      ConvertToEgretMoiceClip(JsonFile, FrameRate, FrameCount, Offset);
      Offset.Free;
      OffsetFile.Free;

      if not DirectoryExists(TargetModelDir) then
        ForceDirectories(TargetModelDir);

      PngFileName := ChangeFileExt(sheetName, '.png');
      TFile.Copy(DirName + sheetName, TargetModelDir + sheetName, True);
      TFile.Copy(DirName + PngFileName, TargetModelDir + PngFileName, True);
    end;
  end;
end;

procedure TForm1.ConvertToEgretMoiceClip(const JsonFile: String; FPS: Single;
FrameCount: Integer; Offset: TList<TXY>);
const
  DIRCONST: Array of String = ['SE', 'SW', 'NW', 'NE', 'S', 'W', 'N', 'E'];
var
  JSON, Frames, egretMoiveClip, egretRes, jsonNode, ResNode, mc, main, Lables,
    LablesNode, Event, egretFrames, egretFrameNode: TQJson;
  PngName: String;
  I: Integer;
begin
  JSON := TQJson.Create();
  JSON.LoadFromFile(JsonFile);

  Frames := JSON.ItemByPath('.frames');
  if Frames = nil then
  begin
    Exit;
  end;
  egretRes := TQJson.Create;
  egretRes.Name := 'res';

  egretFrames := TQJson.Create;
  egretFrames.Name := 'frames';
  egretFrames.DataType := jdtArray;

  for I := 0 to Frames.Count - 1 do
  begin
    jsonNode := Frames.Items[I];
    PngName := jsonNode.Name;
    ResNode := TQJson.Create;
    ResNode.Assign(jsonNode.ItemByPath('frame'));
    ResNode.Name := ChangeFileExt(PngName, '');
    egretRes.Add(ResNode);

    egretFrameNode := TQJson.Create;
    egretFrameNode.AddVariant('res', ResNode.Name);

    if (Offset <> nil) and (I < Offset.Count) then
    begin
      egretFrameNode.AddVariant('x', Offset[I].X);
      egretFrameNode.AddVariant('y', Offset[I].Y);
    end
    else
    begin
      egretFrameNode.AddVariant('x', 0);
      egretFrameNode.AddVariant('y', 0);

    end;

    egretFrames.Add(egretFrameNode);

  end;

  mc := TQJson.Create();
  mc.Name := 'mc';

  main := TQJson.Create;
  mc.Add(main);
  main.Name := 'main';
  main.AddVariant('frameRate', FPS);


  Lables := TQJson.Create;
  Lables.Name := 'labels';
  Lables.DataType := jdtArray;


    LablesNode := TQJson.Create;
    LablesNode.AddVariant('name', 'N');
    LablesNode.AddVariant('frame', 1);
    LablesNode.AddVariant('end', FrameCount
    );
    Lables.Add(LablesNode);

  main.Add(Lables);
  Event := TQJson.Create;
  Event.Name := 'events';
  Event.DataType := jdtArray;
  main.Add(Event);

  main.Add(egretFrames);

  egretMoiveClip := TQJson.Create;
  egretMoiveClip.Add(egretRes);
  egretMoiveClip.Add(mc);
  egretMoiveClip.AddVariant('repacked',true);
  egretMoiveClip.SaveToFile(JsonFile, teUTF8, True, False);
  egretMoiveClip.Free;
end;

{ TChunkIHDRHelper }

function TChunkIHDRHelper.GetPerPixelByteSize: Integer;
begin
  Result := BytesPerRow div Width;
end;

end.
