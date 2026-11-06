unit Atlas.IDE.Build.LastMessages;

// Compilermeldungen des letzten Builds je Projekt (#530, #1455): Base merkt
// sie sich nach jedem Build des Benutzers mit lesbaren Meldungen, auch ohne
// das Modul Build-Pipeline. Der Befehl „Aktuelle Compilermeldungen in die
// Basislinie“ (Modul Prüfregeln) fragt Current. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Build.Messages;

type
  TAtlasIdeLastBuildMessages = class
  private class var
    FCurrent: TAtlasIdeLastBuildMessages;
  private
    FLast: TDictionary<string, TArray<TAtlasCompilerMessage>>;
  public
    /// <summary>Der laufende Speicher (der zuletzt angelegte, bis zu seiner Freigabe); nil ohne. Module fragen ihn
    /// bei jedem Aufruf neu.</summary>
    class function Current: TAtlasIdeLastBuildMessages; static;
    constructor Create;
    destructor Destroy; override;
    /// <summary>Meldungen des letzten Builds von AProject merken.</summary>
    procedure Remember(const AProject: string; const AMessages: TArray<TAtlasCompilerMessage>);
    /// <summary>Warnungen und Hinweise des letzten Builds von AProject, die in die Basislinie können.</summary>
    function Baselinable(const AProject: string): TArray<TAtlasCompilerMessage>;
  end;

implementation

uses
  Atlas.Core.Build.Verdict;

class function TAtlasIdeLastBuildMessages.Current: TAtlasIdeLastBuildMessages;
begin
  Result := FCurrent;
end;

constructor TAtlasIdeLastBuildMessages.Create;
begin
  inherited Create;
  FLast := TDictionary<string, TArray<TAtlasCompilerMessage>>.Create;
  FCurrent := Self;
end;

destructor TAtlasIdeLastBuildMessages.Destroy;
begin
  if FCurrent = Self then
  begin
    FCurrent := nil;
  end;
  FLast.Free;
  inherited;
end;

procedure TAtlasIdeLastBuildMessages.Remember(const AProject: string; const AMessages: TArray<TAtlasCompilerMessage>);
begin
  FLast.AddOrSetValue(AnsiLowerCase(AProject), AMessages);
end;

function TAtlasIdeLastBuildMessages.Baselinable(const AProject: string): TArray<TAtlasCompilerMessage>;
var
  mMessages: TArray<TAtlasCompilerMessage>;
  mMessage: TAtlasCompilerMessage;
begin
  Result := nil;
  if not FLast.TryGetValue(AnsiLowerCase(AProject), mMessages) then
  begin
    Exit;
  end;
  for mMessage in mMessages do
  begin
    if TAtlasBuildVerdicts.Baselinable(mMessage) then
    begin
      Result := Result + [mMessage];
    end;
  end;
end;

end.
