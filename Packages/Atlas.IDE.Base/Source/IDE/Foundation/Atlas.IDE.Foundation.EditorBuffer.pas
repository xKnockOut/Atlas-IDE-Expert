unit Atlas.IDE.Foundation.EditorBuffer;

// Lesen aus dem Editorpuffer der IDE und Umrechnen von Positionen. Der Puffer
// ist UTF-8; LSP-Positionen sind 0-basierte Zeilen und UTF-16-Zeichen, die
// Schreib- und Lesepositionen der IDE sind Byte-Offsets im Puffer. Dazu die
// Frage, ob ein Fenster das Editorfenster ist (Tasten und Klicks im Editor).

interface

uses
  System.SysUtils,
  Winapi.Windows,
  ToolsAPI;

type
  TAtlasEditorBuffer = class
  public
    /// <summary>Ganzer Text des Puffers, auch ungespeichert.</summary>
    class function Text(const ABuffer: IOTAEditBuffer): string; static;
    /// <summary>Text der Zeile ALine (1-basiert) ohne Zeilenende; '' hinter dem Dateiende.</summary>
    class function LineText(const AView: IOTAEditView; ALine: Integer): string; static;
    /// <summary>Erste Tabulatorweite der Editoroptionen, sonst 8.</summary>
    class function TabWidth(const ABuffer: IOTAEditBuffer): Integer; static;
    /// <summary>Einrückung je Ebene aus den Editoroptionen (Blockeinrückung), sonst 2 (#399).</summary>
    class function BlockIndent(const ABuffer: IOTAEditBuffer): Integer; static;
    /// <summary>Byte-Offset im UTF-8-Puffer zu Zeile/Zeichen (0-basiert, UTF-16) in AText.</summary>
    class function ByteOffset(const AText: string; ALine, ACharacter: Integer): Integer; static;
    /// <summary>Zeichenindex (0-basiert) zu ALine/ACharacter in AText.</summary>
    class function CharOffset(const AText: string; ALine, ACharacter: Integer): Integer; static;
    /// <summary>Editoransicht der aktuellen Datei, auch wenn der Fokus gerade in Palette, Menü oder einem
    /// angedockten Fenster liegt; nil ohne offene Quelltextdatei.</summary>
    class function ActiveView: IOTAEditView; static;
    /// <summary>Oberste Editoransicht der IDE (IOTAEditorServices.TopView); nil ohne. Liegt der Fokus außerhalb des
    /// Editors, kann sie fehlen, siehe ActiveView.</summary>
    class function TopView: IOTAEditView; static;
    /// <summary>Wie TopView, aber nil, wenn die Ansicht keinen Puffer hat.</summary>
    class function TopSourceView: IOTAEditView; static;
    /// <summary>Ist AWnd das Editorfenster der IDE (TEditControl)?</summary>
    class function IsEditorWindow(AWnd: HWND): Boolean; static;
  end;

implementation

uses
  Vcl.Controls,
  Atlas.Core.Lsp.TextOffsets;

/// <summary>Ansicht des aktuellen Moduls; bei mehreren Fenstern die zuletzt benutzte.</summary>
function CurrentModuleView: IOTAEditView;
var
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
  mSource: IOTASourceEditor;
  mEditors: IOTAEditorServices;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  mModule := mModules.CurrentModule;
  mIndex := 0;
  while (Result = nil) and (mModule <> nil) and (mIndex < mModule.ModuleFileCount) do
  begin
    if Supports(mModule.ModuleFileEditors[mIndex], IOTASourceEditor, mSource) and (mSource.EditViewCount > 0) then
    begin
      Result := mSource.EditViews[0];
    end;
    Inc(mIndex);
  end;
  // Die zuletzt benutzte Ansicht, falls die Datei in mehreren Fenstern offen ist.
  if (Result <> nil) and Supports(BorlandIDEServices, IOTAEditorServices, mEditors) and
    (mEditors.TopView <> nil) and (mEditors.TopView.Buffer = Result.Buffer) then
  begin
    Result := mEditors.TopView;
  end;
end;

{ TAtlasEditorBuffer }

class function TAtlasEditorBuffer.Text(const ABuffer: IOTAEditBuffer): string;
const
  cChunkSize = 65536;
var
  mReader: IOTAEditReader;
  mBytes: TBytes;
  mPosition, mCount, mUsed, mCapacity: Integer;
begin
  mReader := ABuffer.CreateReader;
  mPosition := 0;
  // Direkt in den Puffer lesen, Kapazität verdoppeln: kein Zwischenstück und kein Umkopieren je Stück.
  mCapacity := cChunkSize;
  mBytes := nil;
  SetLength(mBytes, mCapacity);
  mUsed := 0;
  repeat
    if mUsed + cChunkSize > mCapacity then
    begin
      mCapacity := mCapacity * 2;
      SetLength(mBytes, mCapacity);
    end;
    mCount := mReader.GetText(mPosition, PAnsiChar(@mBytes[mUsed]), cChunkSize);
    if mCount > 0 then
    begin
      Inc(mUsed, mCount);
      Inc(mPosition, mCount);
    end;
  until mCount < cChunkSize;
  Result := TEncoding.UTF8.GetString(mBytes, 0, mUsed);
end;

class function TAtlasEditorBuffer.LineText(const AView: IOTAEditView; ALine: Integer): string;
const
  cMaxLine = 8192;
var
  mCharPos: TOTACharPos;
  mReader: IOTAEditReader;
  mChunk: AnsiString;
  mCount, mStop, mPosition: Integer;
begin
  mCharPos.Line := ALine;
  mCharPos.CharIndex := 0;
  mPosition := AView.CharPosToPos(mCharPos);
  // Unter dem Dateiende liefert der Editor eine Position in der letzten Zeile; deren Text gehört
  // nicht zu ALine (etwa Hover auf Zeile 1800 bei 1793 Zeilen).
  if AView.PosToCharPos(mPosition).Line <> ALine then
  begin
    Exit('');
  end;
  mReader := AView.Buffer.CreateReader;
  SetLength(mChunk, cMaxLine);
  mCount := mReader.GetText(mPosition, PAnsiChar(mChunk), cMaxLine);
  mStop := 1;
  while (mStop <= mCount) and not (mChunk[mStop] in [#13, #10]) do
  begin
    Inc(mStop);
  end;
  Result := UTF8ToString(Copy(mChunk, 1, mStop - 1));
end;

class function TAtlasEditorBuffer.TabWidth(const ABuffer: IOTAEditBuffer): Integer;
const
  cDefaultTabWidth = 8;
var
  mStops: string;
begin
  Result := cDefaultTabWidth;
  if ABuffer.BufferOptions <> nil then
  begin
    mStops := Trim(ABuffer.BufferOptions.TabStops);
    if mStops <> '' then
    begin
      Result := StrToIntDef(mStops.Split([' '])[0], cDefaultTabWidth);
    end;
    if Result < 1 then
    begin
      Result := cDefaultTabWidth;
    end;
  end;
end;

class function TAtlasEditorBuffer.BlockIndent(const ABuffer: IOTAEditBuffer): Integer;
begin
  Result := 2;
  // Blockeinzug steht in den Editoroptionen des Puffers, nicht in BufferOptions.
  if ABuffer.EditOptions <> nil then
  begin
    Result := ABuffer.EditOptions.BlockIndent;
  end;
  if Result < 1 then
  begin
    Result := 2;
  end;
end;

class function TAtlasEditorBuffer.ByteOffset(const AText: string; ALine, ACharacter: Integer): Integer;
begin
  Result := TAtlasTextOffsets.ByteOffset(AText, ALine, ACharacter);
end;

class function TAtlasEditorBuffer.CharOffset(const AText: string; ALine, ACharacter: Integer): Integer;
begin
  Result := TAtlasTextOffsets.CharOffset(AText, ALine, ACharacter);
end;

class function TAtlasEditorBuffer.ActiveView: IOTAEditView;
begin
  // Zuerst das aktuelle Modul: TopView ist leer, solange der Fokus nicht im Editor liegt
  // (Befehl aus Palette, Hauptmenü oder einem angedockten Fenster).
  Result := CurrentModuleView;
  if Result = nil then
  begin
    Result := TopView;
  end;
end;

class function TAtlasEditorBuffer.TopView: IOTAEditView;
var
  mEditors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Result := mEditors.TopView;
  end;
end;

class function TAtlasEditorBuffer.TopSourceView: IOTAEditView;
begin
  Result := TopView;
  if (Result <> nil) and (Result.Buffer = nil) then
  begin
    Result := nil;
  end;
end;

class function TAtlasEditorBuffer.IsEditorWindow(AWnd: HWND): Boolean;
var
  mControl: TWinControl;
begin
  mControl := FindControl(AWnd);
  Result := (mControl <> nil) and mControl.ClassNameIs('TEditControl');
end;

end.
