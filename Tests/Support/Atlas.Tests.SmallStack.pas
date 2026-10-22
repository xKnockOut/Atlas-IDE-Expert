unit Atlas.Tests.SmallStack;

// Testhilfe (#1094): führt Code in einem eigenen Thread mit kleinem Stapel aus.
// So zeigt ein Test ohne riesige Eingaben, dass eine Auswertung den Stapel
// nicht sprengt; ohne Fix läuft der Thread über, mit Fix nicht.

interface

uses
  System.SysUtils;

type
  TSmallStack = record
  public
    /// <summary>Führt AWork in einem Thread mit AStackKb KB Stapel aus und wartet darauf. Ergebnis ist die
    /// Klasse der Ausnahme, mit der AWork endete, sonst ''.</summary>
    class function Run(AStackKb: Integer; const AWork: TProc): string; static;
  end;

implementation

uses
  System.Classes;

type
  TSmallStackThread = class(TThread)
  private
    FWork: TProc;
    FFailure: string;
  protected
    procedure Execute; override;
  public
    constructor Create(AStackKb: Integer; const AWork: TProc);
    property Failure: string read FFailure;
  end;

constructor TSmallStackThread.Create(AStackKb: Integer; const AWork: TProc);
begin
  inherited Create(True, NativeUInt(AStackKb) * 1024);
  FreeOnTerminate := False;
  FWork := AWork;
end;

procedure TSmallStackThread.Execute;
begin
  try
    FWork();
  except
    on E: Exception do
      FFailure := E.ClassName;
  end;
  FWork := nil;
end;

class function TSmallStack.Run(AStackKb: Integer; const AWork: TProc): string;
var
  Thread: TSmallStackThread;
begin
  Thread := TSmallStackThread.Create(AStackKb, AWork);
  try
    Thread.Start;
    Thread.WaitFor;
    Result := Thread.Failure;
  finally
    Thread.Free;
  end;
end;

end.
