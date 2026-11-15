unit Atlas.Core.Debug.ExceptionDialogFlow;

// Entscheidungen beim Exception-Dialog der IDE (#517) außerhalb des Erkennens, ohne IDE prüfbar (#1967): welche
// Formulare Atlas durchsucht, wann es einen Dialog vor dem Zeigen ausblendet, wann das Warten abläuft und welcher
// Knopf gedrückt werden kann. Atlas.IDE.Debug.ExceptionDialog liest die Formulare der VCL.

interface

type
  TAtlasExceptionDialogFlow = class
  public
    /// <summary>Offenes Formular durchsuchen: sichtbar, nicht das Hauptfenster; bereit (AArmed) nur modale, damit
    /// der Takt die IDE nicht durchsucht.</summary>
    class function ScansOpen(AVisible, AMainForm, AArmed, AModal: Boolean): Boolean; static;
    /// <summary>Beim Beginn eines modalen Fensters: noch nicht gezeigtes Formular durchsuchen (unsichtbar, nicht das
    /// Hauptfenster, noch nicht modal).</summary>
    class function ScansHidden(AVisible, AMainForm, AModal: Boolean): Boolean; static;
    /// <summary>Darf Atlas jetzt einen Dialog ausblenden: bereit und noch keiner ausgeblendet?</summary>
    class function MayHide(AArmed, AHidden: Boolean): Boolean; static;
    /// <summary>Warten auf den Dialog nach einem Halt abgelaufen (nicht bereit und mindestens AWatch ms)?</summary>
    class function TimedOut(AArmed: Boolean; ANow, AStartedAt, AWatch: UInt64): Boolean; static;
    /// <summary>Gibt es den Knopf AIndex unter ACount Knöpfen eines gefundenen Dialogs (AFound)?</summary>
    class function CanClick(AFound: Boolean; AIndex, ACount: Integer): Boolean; static;
  end;

implementation

{ TAtlasExceptionDialogFlow }

class function TAtlasExceptionDialogFlow.ScansOpen(AVisible, AMainForm, AArmed, AModal: Boolean): Boolean;
begin
  Result := AVisible and not AMainForm and (AModal or not AArmed);
end;

class function TAtlasExceptionDialogFlow.ScansHidden(AVisible, AMainForm, AModal: Boolean): Boolean;
begin
  Result := not AVisible and not AMainForm and not AModal;
end;

class function TAtlasExceptionDialogFlow.MayHide(AArmed, AHidden: Boolean): Boolean;
begin
  Result := AArmed and not AHidden;
end;

class function TAtlasExceptionDialogFlow.TimedOut(AArmed: Boolean; ANow, AStartedAt, AWatch: UInt64): Boolean;
begin
  Result := not AArmed and (ANow - AStartedAt >= AWatch);
end;

class function TAtlasExceptionDialogFlow.CanClick(AFound: Boolean; AIndex, ACount: Integer): Boolean;
begin
  Result := AFound and (AIndex >= 0) and (AIndex < ACount);
end;

end.
