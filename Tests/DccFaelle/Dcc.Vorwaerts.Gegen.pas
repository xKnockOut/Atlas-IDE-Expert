unit Dcc.Vorwaerts.Gegen;

// #1328, Gegentest zu type-used-before-declaration: Hier soll dcc melden.

interface

type
  TAKlasse = class of TA; // UG1: TA steht erst im nächsten type-Block

type
  TA = class
  end;

implementation

end.
