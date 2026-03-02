
This skill is at a business or mathematical level, but it needs to provide invariants, rules, properties, and types, or just be written in such a way that those objects, invariants, rules, properties, and types, and easily transferable to the type-driven development skill, since this CFMM will be written using the type-driven development skill.


This skill is based on the Guillermo Garis mathematical properties derived from payoffs, invariants for trading functions, and all this. So the three primary papers is The Geometry of a Constant Function Market Makers by Guillermo Garis, Replicating Market Makers, and Replicating Monotonic Payoffs without Oracles. These are the base objects, the base papers we are relying on our framework. This is a framework for building from any payoff CFMM and from any CFMM allowed objects specified on the geometry of market makers, we can derive the other objects such that we have overall the CFMM invariants, the CFMM as a whole. So this skill must have sections or not comments, but essentially, we need to specify a payoff a CFMM invariant, and the skill is user interactive, ask questions, and deriving the LaTeX files that go from one object to another, after such that at the end we have the full CFMM. That's the whole thing. So it's the engineering process.


This is it goes on specs/model/ and has .tex files




(THIS IS SPECIFIC FOR THE L)
# LiquiditySupplySimplest
-----------

The payoff is the simplest,

1 unit change on liqudityGrowth(tickRange(position)) pays 1 unit of account



