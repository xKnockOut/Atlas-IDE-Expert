unit Atlas.Core.Build.Pipeline;

// Verträge und Beiträge der Build-Pipeline, soweit Base sie braucht (#1455,
// ADR 0017 Regel 6): Base reicht dem Modul atlas.buildpipeline die
// gelesenen Compilermeldungen jedes Builds (#528) und den Auftrag, einen
// Build des Benutzers zu bewerten (#530); die Folgen meldet das Modul über
// IAtlasBuildVerdictListener (Atlas.Core.Build.Verdict, Announce). Übernimmt
// keiner die Bewertung (Modul aus), bewertet Base nur nach dem Ergebnis des
// Compilers (CompilerVerdict: ohne Basislinie, build.zeroHints und
// build.warningsAsErrors, die zum Modul gehören) und meldet das ebenso; so
// laufen Benachrichtigung und Tests nach dem Build (#69) auch ohne Modul.
// Builds auf Auftrag für andere Module stehen im Vertrag
// Atlas.IDE.Contracts.BuildPipeline.
// TAtlasBuildPipeline fragt die Registry bei jedem Aufruf neu; ohne ARegistry
// gilt die Registry von Base. Fehler eines Beitrags sammelt es als Text (wie
// TAtlasModuleContributions.ApplySettings), Protokollieren ist Sache des
// Aufrufers.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Verdict;

type
  /// <summary>Gelesene Compilermeldungen eines Builds (#528), Hauptthread.</summary>
  IAtlasCompilerMessagesListener = interface
    ['{28D76957-B5BE-4AB0-8E6C-469673E9C75D}']
    procedure MessagesRead(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject);
  end;

  /// <summary>Bewertung eines Builds des Benutzers mit lesbaren Meldungen (#530), Hauptthread.</summary>
  IAtlasBuildEvaluator = interface
    ['{7A57B5A5-A39B-4709-9063-BFE893CBA09B}']
    /// <summary>True: übernimmt die Bewertung (Folgen über IAtlasBuildVerdictListener); False: Base trägt den Build
    /// ohne Bewertung ein.</summary>
    function Evaluate(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      ASucceeded: Boolean): Boolean;
  end;

  /// <summary>Beiträge der Build-Pipeline über die Registry; jeder Aufruf fragt neu.</summary>
  TAtlasBuildPipeline = class
  public
    /// <summary>Meldungen an jeden IAtlasCompilerMessagesListener; Fehler eines Hörers halten die übrigen nicht an
    /// und stehen im Ergebnis.</summary>
    class function MessagesRead(const AMessages: TArray<TAtlasCompilerMessage>;
      const AProject: TAtlasCompileProject): TArray<string>; overload; static;
    class function MessagesRead(const ARegistry: IAtlasModuleRegistry; const AMessages: TArray<TAtlasCompilerMessage>;
      const AProject: TAtlasCompileProject): TArray<string>; overload; static;
    /// <summary>Bewertung über das laufende Modul; False, wenn keines sie übernimmt. Fehler in AFailures.</summary>
    class function Evaluate(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      ASucceeded: Boolean; out AFailures: TArray<string>): Boolean; overload; static;
    class function Evaluate(const ARegistry: IAtlasModuleRegistry; const AMessages: TArray<TAtlasCompilerMessage>;
      const AProject: TAtlasCompileProject; ASucceeded: Boolean; out AFailures: TArray<string>): Boolean; overload;
      static;
    /// <summary>Bewertung nur nach dem Compiler: ohne Basislinie und ohne Schranken für Hinweise und Warnungen.
    /// </summary>
    class function CompilerVerdict(const AMessages: TArray<TAtlasCompilerMessage>;
      ASucceeded: Boolean): TAtlasBuildVerdict; static;
    /// <summary>Bewertung an jeden IAtlasBuildVerdictListener (Benachrichtigungszentrale, Tests nach dem Build);
    /// Fehler eines Hörers halten die übrigen nicht an und stehen im Ergebnis.</summary>
    class function Announce(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict): TArray<string>; overload; static;
    class function Announce(const ARegistry: IAtlasModuleRegistry; const AMessages: TArray<TAtlasCompilerMessage>;
      const AProject: TAtlasCompileProject; const AVerdict: TAtlasBuildVerdict): TArray<string>; overload; static;
  end;

implementation

uses
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions;

class function TAtlasBuildPipeline.MessagesRead(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject): TArray<string>;
begin
  Result := MessagesRead(AtlasModuleRegistry, AMessages, AProject);
end;

class function TAtlasBuildPipeline.MessagesRead(const ARegistry: IAtlasModuleRegistry;
  const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject): TArray<string>;
var
  mItem: IInterface;
  mListener: IAtlasCompilerMessagesListener;
begin
  Result := nil;
  for mItem in TAtlasModuleContributions.Active(ARegistry, IAtlasCompilerMessagesListener) do
  begin
    if Supports(mItem, IAtlasCompilerMessagesListener, mListener) then
      try
        mListener.MessagesRead(AMessages, AProject);
      except
        on E: Exception do
          Result := Result + [E.ClassName + ': ' + E.Message];
      end;
  end;
end;

class function TAtlasBuildPipeline.Evaluate(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; ASucceeded: Boolean; out AFailures: TArray<string>): Boolean;
begin
  Result := Evaluate(AtlasModuleRegistry, AMessages, AProject, ASucceeded, AFailures);
end;

class function TAtlasBuildPipeline.Evaluate(const ARegistry: IAtlasModuleRegistry;
  const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject; ASucceeded: Boolean;
  out AFailures: TArray<string>): Boolean;
var
  mItem: IInterface;
  mEvaluator: IAtlasBuildEvaluator;
begin
  Result := False;
  AFailures := nil;
  for mItem in TAtlasModuleContributions.Active(ARegistry, IAtlasBuildEvaluator) do
  begin
    if Supports(mItem, IAtlasBuildEvaluator, mEvaluator) then
      try
        if mEvaluator.Evaluate(AMessages, AProject, ASucceeded) then
        begin
          Exit(True);
        end;
      except
        on E: Exception do
          AFailures := AFailures + [E.ClassName + ': ' + E.Message];
      end;
  end;
end;

class function TAtlasBuildPipeline.CompilerVerdict(const AMessages: TArray<TAtlasCompilerMessage>;
  ASucceeded: Boolean): TAtlasBuildVerdict;
begin
  Result := TAtlasBuildVerdicts.Evaluate(AMessages, nil, ASucceeded, Default(TAtlasBuildVerdictSettings));
end;

class function TAtlasBuildPipeline.Announce(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; const AVerdict: TAtlasBuildVerdict): TArray<string>;
begin
  Result := Announce(AtlasModuleRegistry, AMessages, AProject, AVerdict);
end;

class function TAtlasBuildPipeline.Announce(const ARegistry: IAtlasModuleRegistry;
  const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
  const AVerdict: TAtlasBuildVerdict): TArray<string>;
var
  mItem: IInterface;
  mListener: IAtlasBuildVerdictListener;
begin
  Result := nil;
  for mItem in TAtlasModuleContributions.Active(ARegistry, IAtlasBuildVerdictListener) do
  begin
    if Supports(mItem, IAtlasBuildVerdictListener, mListener) then
      try
        mListener.BuildEvaluated(AMessages, AProject, AVerdict);
      except
        on E: Exception do
          Result := Result + [E.ClassName + ': ' + E.Message];
      end;
  end;
end;

end.
