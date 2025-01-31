<?php

namespace App\Http\Security;

use App\Domain\Auth\User;
use Symfony\Component\Security\Core\Authentication\Token\TokenInterface;
use Symfony\Component\Security\Core\Authorization\Voter\Voter;

class AdminVoter extends Voter
{
    public function __construct(private readonly string $appEnv)
    {
    }

    protected function supports(string $attribute, $subject): bool
    {
        return !in_array($attribute, ['IS_IMPERSONATOR']);
    }

    protected function voteOnAttribute(string $attribute, $subject, TokenInterface $token): bool
    {
        $user = $token->getUser();

        if (!$user instanceof User) {
            return false;
        }

        if ('prod' === $this->appEnv) {
            return 'Grafikart' === $user->getUsername() && 1 === $user->getId();
        }

        return 'Grafikart' === $user->getUsername();
    }
}
