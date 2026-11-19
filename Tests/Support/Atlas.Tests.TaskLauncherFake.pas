unit Atlas.Tests.TaskLauncherFake;

// Fälschung für IAtlasTaskLauncher: startet keinen Prozess, sondern schreibt
// mit, was der Ablauf der Projektaufgaben verlangt („launch:<Id>:<Name>:
// <Projekt>“ mit „:show“, wenn die Ausgabe gezeigt wird, „cancel:<Id>“,
// „release:<Id>“). Das Ende eines Laufs meldet der Test selbst über
// TAtlasTaskFlow.Finished. Aufgaben, deren Namen in Refused stehen, lehnt
// Refuses mit dem Grund „<Name> fehlt“ ab; für Aufgaben in Throwing wirft
// Launch (nach dem Mitschreiben) eine Ausnahme „<Name> startet nicht“.

interface

uses
  System.Classes,
  Atlas.Core.Tasks.Contract;

type
  TAtlasTaskLauncherFake = class(TInterfacedObject, IAtlasTaskLauncher)
  private
    FCalls: TStringList;
    FRefused: TStringList;
    FThrowing: TStringList;
    FLastId: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    { IAtlasTaskLauncher }
    function Refuses(const ATask: TAtlasTaskDefinition; out AReason: string): Boolean;
    procedure Launch(AId: Integer; const AProject: string; const ATask: TAtlasTaskDefinition; AShow: Boolean);
    procedure Cancel(AId: Integer);
    procedure Release(AId: Integer);
    /// <summary>Aufrufe, durch Komma getrennt.</summary>
    function CallText: string;
    property Calls: TStringList read FCalls;
    property Refused: TStringList read FRefused;
    property Throwing: TStringList read FThrowing;
    /// <summary>Id des zuletzt gestarteten Laufs (0 = keiner).</summary>
    property LastId: Integer read FLastId;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasTaskLauncherFake }

constructor TAtlasTaskLauncherFake.Create;
begin
  inherited Create;
  FCalls := TStringList.Create;
  FRefused := TStringList.Create;
  FRefused.CaseSensitive := False;
  FThrowing := TStringList.Create;
  FThrowing.CaseSensitive := False;
end;

destructor TAtlasTaskLauncherFake.Destroy;
begin
  FreeAndNil(FThrowing);
  FreeAndNil(FRefused);
  FreeAndNil(FCalls);
  inherited Destroy;
end;

function TAtlasTaskLauncherFake.Refuses(const ATask: TAtlasTaskDefinition; out AReason: string): Boolean;
begin
  AReason := '';
  Result := FRefused.IndexOf(ATask.Name) >= 0;
  if Result then
  begin
    AReason := ATask.Name + ' fehlt';
  end;
end;

procedure TAtlasTaskLauncherFake.Launch(AId: Integer; const AProject: string; const ATask: TAtlasTaskDefinition;
  AShow: Boolean);
var
  mCall: string;
begin
  FLastId := AId;
  mCall := Format('launch:%d:%s:%s', [AId, ATask.Name, AProject]);
  if AShow then
  begin
    mCall := mCall + ':show';
  end;
  FCalls.Add(mCall);
  if FThrowing.IndexOf(ATask.Name) >= 0 then
  begin
    raise EInOutError.Create(ATask.Name + ' startet nicht');
  end;
end;

procedure TAtlasTaskLauncherFake.Cancel(AId: Integer);
begin
  FCalls.Add(Format('cancel:%d', [AId]));
end;

procedure TAtlasTaskLauncherFake.Release(AId: Integer);
begin
  FCalls.Add(Format('release:%d', [AId]));
end;

function TAtlasTaskLauncherFake.CallText: string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to FCalls.Count - 1 do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ',';
    end;
    Result := Result + FCalls[mIndex];
  end;
end;

end.
