unit Atlas.IDE.Rules.IdeErrors;

// Fehler der IDE (#1819, problems.ideErrors) im Modul Prüfregeln: liest
// Error Insight über die Open Tools API (IOTAModuleServices.FindModule,
// IOTAModuleErrors.GetErrors) und gibt die Werte unverändert über
// IAtlasIdeErrors (Atlas.IDE.Contracts.Rules) an Base. Umrechnen, Abgleich mit
// den Atlas-Befunden und Protokoll liegen im Kern von Base. Base fragt nur nach
// einer Prüfung, nie beim Tippen. Nur im Hauptthread.
// Felder von TOTAError laut DocWiki: Text: string; Start, Stop: TOTACharPos
// (Line, CharIndex); Severity: Integer. Ob Error Insight mit Atlas als
// Code-Insight-Manager überhaupt etwas liefert, klärt die Probe EI1–EI4.

interface

uses
  Atlas.IDE.Contracts.Rules;

type
  TAtlasIdeRulesIdeErrors = class(TInterfacedObject, IAtlasIdeErrors)
  public
    function ErrorsOf(const AFileName: string; out AErrors: TArray<TAtlasIdeError>): Boolean;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard;

/// <summary>Error Insight des Moduls zu AFileName; False ohne Modul bzw. ohne IOTAModuleErrors.</summary>
function ReadErrors(const AFileName: string; out AList: TOTAErrors): Boolean;
var
  mServices: IOTAModuleServices;
  mModule: IOTAModule;
  mErrors: IOTAModuleErrors;
begin
  AList := nil;
  Result := False;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  mModule := mServices.FindModule(AFileName);
  if (mModule = nil) or not Supports(mModule, IOTAModuleErrors, mErrors) then
  begin
    Exit;
  end;
  AList := mErrors.GetErrors(AFileName);
  Result := True;
end;

function TAtlasIdeRulesIdeErrors.ErrorsOf(const AFileName: string; out AErrors: TArray<TAtlasIdeError>): Boolean;
var
  mList: TOTAErrors;
  mIndex: Integer;
begin
  AErrors := nil;
  Result := False;
  try
    if not ReadErrors(AFileName, mList) then
    begin
      Exit;
    end;
    SetLength(AErrors, Length(mList));
    for mIndex := 0 to High(mList) do
    begin
      AErrors[mIndex].Text := mList[mIndex].Text;
      AErrors[mIndex].StartLine := mList[mIndex].Start.Line;
      AErrors[mIndex].StartCharIndex := mList[mIndex].Start.CharIndex;
      AErrors[mIndex].StopLine := mList[mIndex].Stop.Line;
      AErrors[mIndex].StopCharIndex := mList[mIndex].Stop.CharIndex;
      AErrors[mIndex].Severity := mList[mIndex].Severity;
    end;
    Result := True;
  except
    on E: Exception do
    begin
      // Eine fehlerhafte Antwort der IDE darf die Prüfung nicht stören: keine Fehler der IDE.
      AErrors := nil;
      Result := False;
      TAtlasGuard.Log('Error Insight: ' + E.ClassName + ': ' + E.Message);
    end;
  end;
end;

end.
