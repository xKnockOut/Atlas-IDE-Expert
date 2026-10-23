unit Atlas.Core.Debug.ExceptionBanner;

// Exception-Leiste beim Debuggen (#783), ohne VCL und Open Tools API:
//   - Mode: Ersetzt die Leiste den Exception-Dialog der IDE (Atlas schließt
//     ihn über „Anhalten“ und zeigt die Leiste), oder bleibt der Dialog und
//     die Leiste kommt danach dazu (Rückfall)? Ersetzt wird nur in einer
//     bekannten IDE-Version (KnownIdeVersion: Delphi 12 und 13), wenn der
//     Dialog mit beiden Knöpfen erkannt ist und der Benutzer den IDE-Dialog
//     für diese Sitzung nicht ausdrücklich verlangt hat.
//   - AutoContinue: still fortsetzen, weil die Klasse (#517) oder Klasse +
//     Datei + Zeile im Projekt („Nur an dieser Stelle ignorieren“) auf der
//     Ignorier-Liste steht. Orte zählen nur mit
//     debug.exceptionBanner.ignoreAtLocation.
//   - Info: Inhalt der Leiste. Der Aufrufstapel ist auf die erste eigene
//     Zeile gekürzt (#578); die Rahmen darüber (RTL, VCL) zählen als
//     „n Ebenen ausgeblendet“.

interface

uses
  Atlas.Core.Debug.CallStack,
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Debug.ExceptionDialog;

type
  {$SCOPEDENUMS ON}
  TAtlasDebugBannerMode = (Off, Replace, Additional);
  TAtlasDebugAutoContinue = (None, ByClass, ByLocation);
  {$SCOPEDENUMS OFF}

  TAtlasDebugBannerInfo = record
    ExceptionClass: string;
    Message: string;
    ThreadText: string;
    /// <summary>Wie oft diese Klasse an dieser Stelle in der Sitzung kam (mit diesem Mal).</summary>
    Count: Integer;
    /// <summary>Index des gezeigten Rahmens im Stapel; -1 ohne.</summary>
    FrameIndex: Integer;
    /// <summary>Rahmen über dem gezeigten (RTL, VCL, ohne Quelltext).</summary>
    Hidden: Integer;
    Routine: string;
    FileName: string;
    /// <summary>1-basiert; 0 = unbekannt.</summary>
    Line: Integer;
    /// <summary>Knopf „Nur an dieser Stelle ignorieren“: Einstellung an, Projekt, Datei und Zeile bekannt.
    /// </summary>
    CanIgnoreLocation: Boolean;
    function HasLocation: Boolean;
    /// <summary>„Unit1.pas:42“; '' ohne Datei.</summary>
    function LocationText: string;
  end;

  TAtlasDebugBannerRules = record
  public const
    /// <summary>CompilerVersion von Delphi 12 und 13; nur dort greift Atlas in den Dialog ein.</summary>
    Delphi12 = 36;
    Delphi13 = 37;
  public
    class function KnownIdeVersion(ACompilerVersion: Double): Boolean; static;
    /// <summary>AEnabled: debug.exceptionBanner. AIdeDialog: Benutzer will in dieser Sitzung den IDE-Dialog.
    /// </summary>
    class function Mode(AEnabled, AKnownVersion, AIdeDialog: Boolean;
      const ADialog: TAtlasDebugDialogScan): TAtlasDebugBannerMode; static;
    class function AutoContinue(AClassIgnored, ALocationIgnored,
      AIgnoreAtLocation: Boolean): TAtlasDebugAutoContinue; static;
    /// <summary>Inhalt der Leiste aus dem Eintrag des Verlaufs (Rahmen, Ort und Zähler gesetzt). AMainLabel:
    /// Text für den Hauptthread ohne Namen.</summary>
    class function Info(const AException: TAtlasDebugException; AJustMyCode: Boolean; const AProject,
      AMainLabel: string; AIgnoreAtLocation: Boolean): TAtlasDebugBannerInfo; static;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Core.Debug.OwnCode;

{ TAtlasDebugBannerInfo }

function TAtlasDebugBannerInfo.HasLocation: Boolean;
begin
  Result := (FileName <> '') and (Line > 0);
end;

function TAtlasDebugBannerInfo.LocationText: string;
begin
  Result := '';
  if FileName = '' then
    Exit;
  Result := ExtractFileName(FileName);
  if Line > 0 then
    Result := Result + ':' + IntToStr(Line);
end;

{ TAtlasDebugBannerRules }

class function TAtlasDebugBannerRules.KnownIdeVersion(ACompilerVersion: Double): Boolean;
begin
  Result := SameValue(ACompilerVersion, Delphi12) or SameValue(ACompilerVersion, Delphi13);
end;

class function TAtlasDebugBannerRules.Mode(AEnabled, AKnownVersion, AIdeDialog: Boolean;
  const ADialog: TAtlasDebugDialogScan): TAtlasDebugBannerMode;
begin
  if not AEnabled then
    Result := TAtlasDebugBannerMode.Off
  else if AKnownVersion and not AIdeDialog and ADialog.CanContinue then
    Result := TAtlasDebugBannerMode.Replace
  else
    Result := TAtlasDebugBannerMode.Additional;
end;

class function TAtlasDebugBannerRules.AutoContinue(AClassIgnored, ALocationIgnored,
  AIgnoreAtLocation: Boolean): TAtlasDebugAutoContinue;
begin
  if AClassIgnored then
    Result := TAtlasDebugAutoContinue.ByClass
  else if ALocationIgnored and AIgnoreAtLocation then
    Result := TAtlasDebugAutoContinue.ByLocation
  else
    Result := TAtlasDebugAutoContinue.None;
end;

class function TAtlasDebugBannerRules.Info(const AException: TAtlasDebugException; AJustMyCode: Boolean;
  const AProject, AMainLabel: string; AIgnoreAtLocation: Boolean): TAtlasDebugBannerInfo;
var
  Frames: TAtlasDebugFrames;
begin
  Result := Default(TAtlasDebugBannerInfo);
  Result.ExceptionClass := AException.ExceptionClass;
  Result.Message := AException.Message;
  Result.ThreadText := AException.ThreadText(AMainLabel);
  Result.Count := Max(1, AException.Count);
  Result.Routine := AException.Routine;
  Result.FileName := AException.FileName;
  Result.Line := AException.Line;
  Frames := AException.Frames;
  Result.FrameIndex := TAtlasDebugOwnCode.LocationIndex(Frames, AJustMyCode);
  if Result.FrameIndex >= 0 then
  begin
    Result.Hidden := Result.FrameIndex;
    Result.Routine := Frames[Result.FrameIndex].Routine;
    Result.FileName := Frames[Result.FrameIndex].FileName;
    Result.Line := Frames[Result.FrameIndex].Line;
  end
  else if (Result.Routine = '') and (Frames <> nil) then
    Result.Routine := Frames[0].Routine;
  Result.CanIgnoreLocation := AIgnoreAtLocation and (AProject <> '') and Result.HasLocation;
end;

end.
