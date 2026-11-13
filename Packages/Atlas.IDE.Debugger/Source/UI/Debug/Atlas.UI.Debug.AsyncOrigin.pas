unit Atlas.UI.Debug.AsyncOrigin;

// Texte zur Herkunft eingereihter Methoden (#859): Überschrift „Eingereiht mit TThread.Queue von Thread 4120“, Zeilen
// des damaligen Stapels (Bibliothek zusammengefasst zu „5 Rahmen der Bibliothek“) und die Zeile der Statusleiste.

interface

uses
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.AsyncOrigin;

type
  TAtlasAsyncOriginTexts = class
  private
    /// <summary>ACount Rahmen der Bibliothek als eine Zeile anhängen (ohne, wenn 0); ACount danach 0.</summary>
    class procedure AddLibrary(var ARows: TArray<string>; var AFrameIndex: TArray<Integer>; var ACount: Integer);
      static;
  public
    class function Title(const AEntry: TAtlasAsyncEntry; AKind: TAtlasAsyncKind): string; static;
    /// <summary>„TForm1.Button1Click (Unit1.pas:30)“; ohne Quelltext nur die Routine.</summary>
    class function FrameText(const AFrame: TAtlasDebugFrame): string; static;
    /// <summary>Zeilen des Stapels, oberster Rahmen zuerst: eigener Code je Zeile, Rahmen der Bibliothek dazwischen
    /// in einer Zeile. AFrameIndex nennt je Zeile den Rahmen (-1 für die zusammengefassten).</summary>
    class function Rows(const AFrames: TAtlasDebugFrames; out AFrameIndex: TArray<Integer>): TArray<string>; static;
    class function NoneText(AKind: TAtlasAsyncKind): string; static;
    class function StatusText(ASites: Integer): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Debug.Strings,
  Atlas.UI.Debug.Deadlocks;

class function TAtlasAsyncOriginTexts.Title(const AEntry: TAtlasAsyncEntry; AKind: TAtlasAsyncKind): string;
begin
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.AsyncOriginTitle,
    [TAtlasAsyncSites.KindName(AKind), AEntry.ThreadId]);
end;

class function TAtlasAsyncOriginTexts.FrameText(const AFrame: TAtlasDebugFrame): string;
begin
  Result := TAtlasDebugWaitTexts.ShortRoutine(AFrame.Routine);
  if AFrame.HasSource then
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.AsyncOriginFrame,
      [Result, ExtractFileName(AFrame.FileName), AFrame.Line]);
  end;
end;

class procedure TAtlasAsyncOriginTexts.AddLibrary(var ARows: TArray<string>; var AFrameIndex: TArray<Integer>;
  var ACount: Integer);
begin
  if ACount > 0 then
  begin
    ARows := ARows + [TAtlasDebugStrings.Fmt(TAtlasDebugTextId.AsyncOriginLibrary, [ACount])];
    AFrameIndex := AFrameIndex + [-1];
  end;
  ACount := 0;
end;

class function TAtlasAsyncOriginTexts.Rows(const AFrames: TAtlasDebugFrames;
  out AFrameIndex: TArray<Integer>): TArray<string>;
var
  mIndex, mLibrary: Integer;
begin
  Result := nil;
  AFrameIndex := nil;
  mLibrary := 0;
  for mIndex := 0 to High(AFrames) do
  begin
    if not AFrames[mIndex].Own then
    begin
      Inc(mLibrary);
      Continue;
    end;
    // Die Rahmen der Bibliothek davor als eine Zeile.
    AddLibrary(Result, AFrameIndex, mLibrary);
    Result := Result + [FrameText(AFrames[mIndex])];
    AFrameIndex := AFrameIndex + [mIndex];
  end;
  AddLibrary(Result, AFrameIndex, mLibrary);
end;

class function TAtlasAsyncOriginTexts.NoneText(AKind: TAtlasAsyncKind): string;
begin
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.AsyncOriginNone, [TAtlasAsyncSites.KindName(AKind)]);
end;

class function TAtlasAsyncOriginTexts.StatusText(ASites: Integer): string;
begin
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.AsyncOriginStatus, [ASites]);
end;

end.
