unit Atlas.Linux.Diagnostics.StackTrace;

// Platform-Feature "Diagnostics" für Linux (#1109): Gegenstück zu
// Atlas.Windows.Diagnostics.StackTrace. Free Pascal hält zu jeder Exception die
// Rücksprungadressen bis zum raise bereit (ExceptAddr, ExceptFrames);
// BackTraceStrFunc formatiert sie, mit Zeilennummern, wenn der Server mit
// -gl übersetzt ist (Build-AtlasServer.sh). Install und Uninstall gibt es nur
// der gleichen Form halber: Die Laufzeit sammelt die Adressen von sich aus.

interface

uses
  System.SysUtils;

type
  TStackTrace = record
  public
    class procedure Install; static;
    class procedure Uninstall; static;
    class function Installed: Boolean; static;
    /// <summary>Aktuelle Aufrufkette, eine Zeile je Rücksprungadresse.</summary>
    class function Current: string; static;
    /// <summary>Aufrufkette der gerade behandelten Exception AError bis zum raise; '' außerhalb des
    /// except-Blocks dieser Exception.</summary>
    class function OfException(AError: Exception): string; static;
    /// <summary>Formatiert eine Adresse (Unit, Routine und Zeile, soweit bekannt).</summary>
    class function DescribeAddress(AAddress: Pointer): string; static;
  end;

implementation

var
  GInstalled: Boolean;

class procedure TStackTrace.Install;
begin
  GInstalled := True;
end;

class procedure TStackTrace.Uninstall;
begin
  GInstalled := False;
end;

class function TStackTrace.Installed: Boolean;
begin
  Result := GInstalled;
end;

class function TStackTrace.DescribeAddress(AAddress: Pointer): string;
begin
  Result := Trim(string(BackTraceStrFunc(AAddress)));
end;

class function TStackTrace.Current: string;
var
  mFrames: array[0..63] of CodePointer;
  mCount, mIndex: Integer;
begin
  Result := '';
  mCount := CaptureBacktrace(1, Length(mFrames), @mFrames[0]);
  for mIndex := 0 to mCount - 1 do
  begin
    Result := Result + DescribeAddress(mFrames[mIndex]) + sLineBreak;
  end;
end;

class function TStackTrace.OfException(AError: Exception): string;
var
  mFrames: PCodePointer;
  mIndex: Integer;
begin
  Result := '';
  if (AError = nil) or (ExceptObject <> AError) then
  begin
    Exit;
  end;
  Result := DescribeAddress(ExceptAddr) + sLineBreak;
  mFrames := ExceptFrames;
  for mIndex := 0 to ExceptFrameCount - 1 do
  begin
    Result := Result + DescribeAddress(mFrames[mIndex]) + sLineBreak;
  end;
end;

end.
