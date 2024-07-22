// SPDX-License-Identifier: LGPL-3.0-or-later
pragma solidity ^0.8;

/// Contract that exposes three functions that must be called in the expected
/// order. The last called function is stored in the state as `lastCall`.
contract CallOrderEnforcer {
    enum Called {
        None,
        Pre,
        Intra,
        Post
    }

    Called public lastCall = Called.None;

    function pre() public {
        require(lastCall == Called.None, "called `pre` but there should have been no other calls before");
        lastCall = Called.Pre;
    }

    function intra() public {
        require(lastCall == Called.Pre, "called `intra` but previous call wasn't `pre`");
        lastCall = Called.Intra;
    }

    function post() public {
        require(lastCall == Called.Intra, "called `post` but previous call wasn't `intra`");
        lastCall = Called.Post;
    }
}
