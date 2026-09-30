using UnityEngine;

namespace MOI
{
    /// <summary>
    /// Base for anything that performs during one beat. The director pushes normalised beat time
    /// every frame, so behaviours are pure functions of the clock and survive skipping and scrubbing.
    /// </summary>
    public abstract class BeatBehaviour : MonoBehaviour
    {
        public string beatId;

        /// <param name="active">True while the master clock is inside this beat.</param>
        /// <param name="t">0..1 through the beat. Only meaningful while active.</param>
        public abstract void Evaluate(bool active, float t);
    }
}
